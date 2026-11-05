# Rows on a split: adding one, naming one, removing one.
#
# Adding and removing answer with Turbo Streams, because one change moves money
# in every other row — the amounts and the remaining total have to be redrawn
# together or the screen would show a split that does not add up.
#
# Naming answers with a Turbo Frame instead: it changes one row's name and
# nothing else, so there is nothing else to redraw.
class ParticipantsController < ApplicationController
  before_action :set_split
  before_action :set_participant, only: %i[update destroy]

  def create
    if @split.participants.size >= SplitMath::PEOPLE_RANGE.max
      return refuse("A split can have at most #{SplitMath::PEOPLE_RANGE.max} people.")
    end

    @split.participants.build(position: @split.participants.size + 1)
    respread_and_save
  end

  def update
    @participant.person = chosen_person
    @participant.save!

    render partial: "participants/participant_name",
           locals: { participant: @participant, split: @split }
  end

  def destroy
    if @split.participants.size <= SplitMath::PEOPLE_RANGE.min
      return refuse("A split needs at least #{SplitMath::PEOPLE_RANGE.min} people.")
    end

    @participant.destroy!
    @split.participants.reload
    @split.renumber_positions
    respread_and_save
  end

  private

  def set_split
    @split = Split.owned_by(owner_token).find(params[:split_id])
  end

  def set_participant
    @participant = @split.participants.find(params[:id])
  end

  # Scoped to this browser: one organizer cannot staple another's saved people
  # onto their split by guessing an id. A blank id clears the name back to a
  # placeholder.
  def chosen_person
    person_id = params.expect(participant: [ :person_id ])[:person_id]
    return nil if person_id.blank?

    Person.owned_by(owner_token).find(person_id)
  end

  # The amounts belong to SplitMath, not to the row that just appeared or left.
  def respread_and_save
    @split.even? ? @split.apply_even_split : @split.apply_custom_split

    if @split.save
      render turbo_stream: [
        turbo_stream.replace("participants", partial: "splits/participants", locals: { split: @split }),
        turbo_stream.replace("remaining", partial: "splits/remaining", locals: { split: @split }),
        turbo_stream.replace("flash", partial: "shared/flash", locals: { message: nil })
      ]
    else
      refuse(@split.errors.full_messages.to_sentence)
    end
  end

  def refuse(message)
    render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash", locals: { message: message }),
           status: :unprocessable_entity
  end
end
