class SplitsController < ApplicationController
  before_action :set_quick_split_limits, only: %i[new create edit update]
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
      redirect_to split_path(@split)
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

  # The same composer as a new split, opened on the people step with this
  # split's rows already in it. Each row carries its participant id so saving
  # can keep who has already paid.
  def edit
    @draft_rows = @split.participants.map { |participant| draft_row_for(participant) }
    @people_count = @draft_rows.size
  end

  # The composer submits the whole draft again, so an edit is "replace the rows
  # with these" through the same SplitDraft a new split uses. One path means
  # one set of rules about what a saved split may look like.
  def update
    rows = quick_split_params[:draft_rows]
    @split.assign_attributes(title: quick_split_params[:title].presence || @split.title,
                             amount: quick_split_params[:amount])

    if rows.present? && SplitDraft.new(@split, rows).save
      redirect_to split_path(@split), notice: "Saved."
    else
      @draft_rows = Array(rows).map(&:to_h)
      @people_count = @draft_rows.size
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
      draft_rows: [ [ :id, :person_id, :name, :payment_method, :phone_number, :amount_cents, :locked ] ] } ])
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

  def draft_row_for(participant)
    person = participant.person
    { id: participant.id, person_id: person&.id, name: person&.name,
      payment_method: participant.payment_method, phone_number: person&.display_phone_number,
      portrait_index: (helpers.avatar_portrait_index(person) if person),
      amount_cents: participant.amount_cents, locked: participant.locked? ? "1" : "0" }
  end
end
