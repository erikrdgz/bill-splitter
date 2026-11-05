# Rows on a split: adding one, naming one, removing one.
#
# Adding and removing answer with Turbo Streams, because one change can move
# money in every other row — the amounts and the remaining total have to be
# redrawn together or the screen would show a split that does not add up.
#
# Naming answers with a Turbo Frame instead: it changes one row's name and
# nothing else, so there is nothing else to redraw.
class ParticipantsController < ApplicationController
  before_action :set_split
  before_action :set_participant, only: %i[update destroy]

  def create
    # Quick add always grows the group; connecting an existing row is separate.
    if params[:person_id].present?
      person = Person.owned_by(owner_token).find(params[:person_id])
      @participant = @split.participants.find { |row| row.person_id == person.id }
      return render_connection if @participant

    end

    if @split.participants.size >= SplitMath::PEOPLE_RANGE.max
      return refuse("A split can have at most #{SplitMath::PEOPLE_RANGE.max} people.")
    end

    @split.participants.build(position: @split.participants.size + 1, amount_cents: 0, person: person)

    # Even mode re-evens everyone. Custom mode gives the new row nothing and
    # leaves the organizer's allocation alone: the split still adds up, and the
    # remaining figure shows them there is nothing yet to give this person.
    @split.apply_even_split if @split.even?

    if @split.custom? && @split.save
      render turbo_stream: [
        turbo_stream.append("participants", partial: "participants/participant_row",
          locals: { participant: @split.participants.last, participant_counter: @split.participants.size - 1, split: @split, removable: true }),
        turbo_stream.replace("recent_friends", partial: "splits/recent_friends",
          locals: { split: @split, people: Person.owned_by(owner_token).recently_used.limit(12) })
      ]
    else
      save_and_redraw
    end
  end

  def update
    @participant.person = chosen_person
    @participant.save!

    render_connection
  end

  def destroy
    if @split.participants.size <= SplitMath::PEOPLE_RANGE.min
      return refuse("A saved split needs at least one person.")
    end

    # The leaving row's share has to go somewhere or the split stops adding up.
    # Untouched rows absorb it; if the organizer has set every row by hand there
    # is nowhere for it to go, and saying so beats silently overruling one of
    # their amounts.
    if @split.custom? && no_row_can_absorb?
      return refuse("Unlock a row first, so #{@participant.display_name}'s share has " \
                    "somewhere to go.")
    end

    @participant.destroy!
    @split.participants.reload
    @split.renumber_positions
    @split.even? ? @split.apply_even_split : @split.apply_custom_split

    save_and_redraw
  end

  private

  # Naming a seat changes no money. Keep the other rows in place so their
  # unsaved custom allocations survive a quick add.
  def render_connection
    render turbo_stream: [
      turbo_stream.replace(ActionView::RecordIdentifier.dom_id(@participant, :name),
                           partial: "participants/participant_name",
                           locals: { participant: @participant, split: @split }),
      turbo_stream.replace("recent_friends", partial: "splits/recent_friends",
                           locals: { split: @split, people: Person.owned_by(owner_token).recently_used.limit(12) })
    ]
  end

  def set_split
    @split = Split.owned_by(owner_token).find(params[:split_id])
  end

  def set_participant
    @participant = @split.participants.find(params[:id])
  end

  def no_row_can_absorb?
    @split.participants.reject { |participant| participant == @participant }.all?(&:locked?)
  end

  # Scoped to this browser: one organizer cannot staple another's saved people
  # onto their split by guessing an id. A blank id clears the name back to a
  # placeholder.
  def chosen_person
    person_id = params.expect(participant: [ :person_id ])[:person_id]
    return nil if person_id.blank?

    Person.owned_by(owner_token).find(person_id)
  end

  def save_and_redraw
    if @split.save
      render turbo_stream: [
        turbo_stream.replace("participants", partial: "splits/participants", locals: { split: @split }),
        turbo_stream.replace("recent_friends", partial: "splits/recent_friends",
                             locals: { split: @split, people: Person.owned_by(owner_token).recently_used.limit(12) }),
        turbo_stream.replace("remaining", partial: "splits/remaining", locals: { split: @split }),
        turbo_stream.replace("flash", partial: "shared/flash", locals: { message: nil })
      ]
    else
      refuse(@split.errors.full_messages.to_sentence)
    end
  end

  def refuse(message)
    render turbo_stream: turbo_stream.replace("flash", partial: "shared/flash",
                                              locals: { message: message, alert: true }),
           status: :unprocessable_entity
  end
end
