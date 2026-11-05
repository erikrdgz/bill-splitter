# The people picker behind a participant row, and the payment handles a saved
# person can be asked for money at.
#
# index is the search. It renders one template that holds two nested Turbo
# Frames: the row's name frame, and the results frame inside it. Opening the
# picker targets the outer frame; typing targets the inner one. Turbo picks the
# matching frame out of the same response either way, so there is no separate
# "just the results" endpoint to keep in step.
class PeopleController < ApplicationController
  before_action :set_participant, only: %i[index create]
  before_action :set_person, only: %i[show edit update]
  before_action :set_requesting_participant, only: %i[edit update]
  before_action :set_query, only: %i[index]

  def index
    @people = matching_people
  end

  # Read-only, browser-owned contacts for an unsaved draft. Blank input shows
  # no suggestions; a name is never saved merely because it was searched.
  def search
    query = params[:query].to_s.strip.first(40)
    people = query.present? ? Person.owned_by(owner_token).matching(query).by_name.limit(20) : []
    render json: people.map { |person| { id: person.id, name: person.name,
      venmo: person.venmo_handle, cashApp: person.cashapp_cashtag, zelle: person.zelle_contact } }
  end

  # "Add [name] as a new person": saves the name for next time and puts it on
  # this row, in one request, because that is one decision for the organizer.
  def create
    @person = Person.new(person_params.merge(owner_token: owner_token))

    if @person.save
      @participant.update!(person: @person)
      render turbo_stream: [
        turbo_stream.replace(ActionView::RecordIdentifier.dom_id(@participant, :name),
                             partial: "participants/participant_name",
                             locals: { participant: @participant, split: @split }),
        turbo_stream.replace("recent_friends", partial: "splits/recent_friends",
                             locals: { split: @split, people: Person.owned_by(owner_token).recently_used.limit(12) })
      ]
    else
      @query = @person.name.to_s
      @people = matching_people
      render :index, status: :unprocessable_entity
    end
  end

  # Restores the display frame: what Cancel goes back to.
  def show
    render partial: "people/payment_details", locals: { person: @person }
  end

  def edit
  end

  def update
    if @person.update(payment_handle_params)
      render_saved_handles
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # A participant is reachable only through a split this browser owns, so the
  # picker cannot be pointed at somebody else's row.
  def set_participant
    @participant = owned_participants.find(params[:participant_id])
    @split = @participant.split
  end

  # Optional: set when the handle form was opened from a split's request list,
  # so the answer can redraw that row.
  def set_requesting_participant
    @participant = owned_participants.find_by(id: params[:participant_id])
    @split = @participant&.split
  end

  def owned_participants
    Participant.joins(:split).where(splits: { owner_token: owner_token })
  end

  def set_person
    @person = Person.owned_by(owner_token).find(params[:id])
  end

  def set_query
    @query = params[:query].to_s
  end

  # A new handle means new buttons beside it, so the whole request row is
  # redrawn rather than just the frame holding the handles. Opened from
  # anywhere else, there is no row to redraw and the frame is the whole answer.
  def render_saved_handles
    if @participant
      render turbo_stream: turbo_stream.replace(
        ActionView::RecordIdentifier.dom_id(@participant, :request),
        partial: "payments/request_row",
        locals: { participant: @participant, split: @split }
      )
    else
      render partial: "people/payment_details", locals: { person: @person }
    end
  end

  # Capped: the picker is a short list to tap, not a directory to page through.
  def matching_people
    Person.owned_by(owner_token).matching(@query).by_name.limit(20)
  end

  def person_params
    params.expect(person: [ :name ])
  end

  # Only the handles. The name is set when the person is created, and renaming
  # somebody from a payment form would be a surprise.
  def payment_handle_params
    params.expect(person: %i[venmo_handle cashapp_cashtag zelle_contact])
  end
end
