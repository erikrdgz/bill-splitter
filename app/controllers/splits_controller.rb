class SplitsController < ApplicationController
  before_action :set_quick_split_limits, only: %i[new create]
  before_action :set_split, only: %i[show edit update]

  # The quick split screen. It touches no database: the organizer has not asked
  # us to remember anything yet, so there is nothing to save and nothing to look
  # up. The shares on screen are worked out in the browser by QuickSplitLogic,
  # which mirrors SplitMath so the numbers move with every keystroke.
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
      title: default_title,
      amount: quick_split_params[:amount],
      owner_token: owner_token
    )
    build_participants(submitted_people_count)
    @split.apply_even_split

    if @split.save
      redirect_to edit_split_path(@split)
    else
      @people_count = submitted_people_count
      render :new, status: :unprocessable_entity
    end
  end

  # The organizer's own view of a split: who has paid, what is still owed, and
  # the link to hand around.
  def show
  end

  def edit
  end

  # Saves the title and the total together, then hands the amounts back to
  # SplitMath rather than trusting anything the form said about them. In even
  # mode that is the whole story; custom mode keeps the locked rows.
  def update
    @split.assign_attributes(split_params)
    @split.even? ? @split.apply_even_split : @split.apply_custom_split

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

  def set_quick_split_limits
    @minimum_people = SplitMath::PEOPLE_RANGE.min
    @maximum_people = SplitMath::PEOPLE_RANGE.max
    @maximum_total_cents = SplitMath::MAXIMUM_TOTAL_CENTS
  end

  def quick_split_params
    params.expect(split: %i[amount people_count])
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
    quick_split_params[:people_count].to_i
  end

  # Clamped only at the ends that would hurt: below 1 the even split has nobody
  # to divide between, and far above the maximum a forged request could ask us
  # to build a million rows. One over the maximum still fails validation with
  # the message the organizer should see.
  def build_participants(people_count)
    safe_count = people_count.clamp(1, SplitMath::PEOPLE_RANGE.max + 1)

    safe_count.times { |index| @split.participants.build(position: index + 1) }
  end
end
