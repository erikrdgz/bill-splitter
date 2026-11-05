# The people picker behind a participant row.
#
# index is the search. It renders one template that holds two nested Turbo
# Frames: the row's name frame, and the results frame inside it. Opening the
# picker targets the outer frame; typing targets the inner one. Turbo picks the
# matching frame out of the same response either way, so there is no separate
# "just the results" endpoint to keep in step.
class PeopleController < ApplicationController
  before_action :set_participant
  before_action :set_query, only: %i[index]

  def index
    @people = matching_people
  end

  # "Add [name] as a new person": saves the name for next time and puts it on
  # this row, in one request, because that is one decision for the organizer.
  def create
    @person = Person.new(person_params.merge(owner_token: owner_token))

    if @person.save
      @participant.update!(person: @person)
      render partial: "participants/participant_name",
             locals: { participant: @participant, split: @split }
    else
      @query = @person.name.to_s
      @people = matching_people
      render :index, status: :unprocessable_entity
    end
  end

  private

  # A participant is reachable only through a split this browser owns, so the
  # picker cannot be pointed at somebody else's row.
  def set_participant
    @participant = Participant.joins(:split)
                              .where(splits: { owner_token: owner_token })
                              .find(params[:participant_id])
    @split = @participant.split
  end

  def set_query
    @query = params[:query].to_s
  end

  # Capped: the picker is a short list to tap, not a directory to page through.
  def matching_people
    Person.owned_by(owner_token).matching(@query).by_name.limit(20)
  end

  def person_params
    params.expect(person: [ :name ])
  end
end
