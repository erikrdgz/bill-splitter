class SplitsController < ApplicationController
  before_action :set_quick_split_limits, only: %i[new create]
  before_action :set_recent_people, only: %i[new create edit update]
  before_action :set_split, only: %i[show edit update]

  # History: this browser's splits, newest first.
  #
  # includes(:participants) matters here. Every row shows what is still owed,
  # which adds up that split's participants — without it this is one query per
  # split on the page, and the page is a list.
  def index
    @splits = Split.owned_by(owner_token).newest_first.includes(:participants)
  end

  # The draft reads this browser's recent people, but writes nothing until
  # Save or Review. QuickSplitLogic previews shares; the server recomputes on create.
  def new
    @split = Split.new
    @people_count = @minimum_people
  end

  # The first time anything is written down. The browser has been showing shares
  # all along, but they were never sent: the server works them out again with
  # SplitMath from the amount and the head count, so what is stored is the
  # server's arithmetic and not the browser's.
  def create
    @split = Split.new(
      title: quick_split_params[:title].presence || default_title,
      amount: quick_split_params[:amount],
      owner_token: owner_token
    )
    rows = quick_split_params[:draft_rows]
    if rows.present?
      @draft_rows = rows.map(&:to_h)
      saved = SplitDraft.new(@split, rows).save
    else
      build_participants(submitted_people_count)
      selected_people.each_with_index { |person, index| @split.participants[index].person = person }
      @split.apply_even_split
      saved = @split.save
    end

    if saved
      redirect_to params[:intent] == "request" ? split_path(@split) : edit_split_path(@split)
    else
      @people_count = rows.present? ? rows.size : submitted_people_count
      render :new, status: :unprocessable_entity
    end
  end

  # The organizer's own view of a split: who has paid, what is still owed, the
  # link to hand around, and the ways to ask for the money.
  def show
    @payment_profile = PaymentProfile.for_owner(owner_token)
  end

  def edit
  end

  # In even mode the amounts are the server's to work out, so whatever the form
  # said about them is thrown away and SplitMath decides.
  #
  # In custom mode they are the organizer's own allocation, so they are taken as
  # posted and only checked. The server still has the final say — it just says
  # "no" rather than "here is what you meant". A split whose rows do not add up
  # to its total is refused by the validation, which is the whole point of
  # custom mode having a remaining figure to work down to zero.
  def update
    @split.assign_attributes(split_params)
    @split.apply_even_split if @split.even?

    if @split.save
      redirect_to edit_split_path(@split), notice: "Saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_split
    # Scoped to this browser, so another organizer's split is simply not found.
    @split = Split.owned_by(owner_token).find(params[:id])
  end

  def set_recent_people
    DevelopmentContacts.seed_for(owner_token)
    @recent_people = Person.owned_by(owner_token).recently_used.limit(12)
  end

  def selected_people
    @selected_people ||= Array(quick_split_params[:person_ids]).reject(&:blank?).uniq.first(SplitMath::PEOPLE_RANGE.max).map do |id|
      Person.owned_by(owner_token).find(id)
    end
  end

  def set_quick_split_limits
    @minimum_people = 0
    @maximum_people = SplitMath::PEOPLE_RANGE.max
    @maximum_total_cents = SplitMath::MAXIMUM_TOTAL_CENTS
  end

  def quick_split_params
    params.expect(split: [ :amount, :people_count, :title, { person_ids: [],
      draft_rows: [ [ :person_id, :name, :payment_method, :handle, :amount_cents, :locked ] ] } ])
  end

  def split_params
    params.expect(
      split: [ :title, :amount, :split_mode,
               { participants_attributes: [ [ :id, :amount_cents, :locked ] ] } ]
    )
  end

  # The quick split has no title field — naming the split is what the editor is
  # for — so it gets today's date until the organizer says otherwise.
  def default_title
    "Split on #{Date.current.strftime('%B %-d')}"
  end

  def submitted_people_count
    [ quick_split_params[:people_count].to_i, selected_people.size ].max
  end

  # Keep an empty submission empty so validation refuses it. A forged request
  # can build at most one row above the limit, enough for a useful error.
  def build_participants(people_count)
    safe_count = people_count.clamp(0, SplitMath::PEOPLE_RANGE.max + 1)

    safe_count.times { |index| @split.participants.build(position: index + 1) }
  end
end
