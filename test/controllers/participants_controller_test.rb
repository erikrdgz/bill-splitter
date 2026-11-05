require "test_helper"

class ParticipantsControllerTest < ActionDispatch::IntegrationTest
  # The spec's test.
  test "adding a participant answers with a Turbo Stream that includes the new row" do
    split = create_split(amount: "100", people_count: 2)

    assert_difference -> { split.participants.count }, 1 do
      post split_participants_url(split), as: :turbo_stream
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match "Person 3", response.body
  end

  test "adding a participant respreads the money so the split still adds up" do
    split = create_split(amount: "100", people_count: 2)

    post split_participants_url(split), as: :turbo_stream
    split.reload

    assert_equal [ 3334, 3333, 3333 ], split.participants.map(&:amount_cents)
    assert_equal 0, split.remaining_cents
  end

  test "the new row goes on the end" do
    split = create_split(amount: "100", people_count: 2)

    post split_participants_url(split), as: :turbo_stream

    assert_equal [ 1, 2, 3 ], split.reload.participants.map(&:position)
  end

  test "the stream redraws the remaining total too" do
    split = create_split(amount: "100", people_count: 2)

    post split_participants_url(split), as: :turbo_stream

    assert_match "remaining", response.body
  end

  test "a twenty-first person is refused" do
    split = create_split(amount: "100", people_count: 20)

    assert_no_difference -> { split.participants.count } do
      post split_participants_url(split), as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "at most 20 people", response.body
  end

  # Removing.

  test "removing a participant takes the row away and respreads the rest" do
    split = create_split(amount: "100", people_count: 3)
    removed = split.participants.second

    assert_difference -> { split.participants.count }, -1 do
      delete split_participant_url(split, removed), as: :turbo_stream
    end

    split.reload

    assert_equal [ 5000, 5000 ], split.participants.map(&:amount_cents)
    assert_equal 0, split.remaining_cents
  end

  # Positions are what placeholders are named from, so a gap would show up on
  # screen as "Person 1, Person 3".
  test "removing a participant closes the gap in the positions" do
    split = create_split(amount: "100", people_count: 4)

    delete split_participant_url(split, split.participants.second), as: :turbo_stream

    split.reload

    assert_equal [ 1, 2, 3 ], split.participants.map(&:position)
    assert_equal [ "Person 1", "Person 2", "Person 3" ], split.participants.map(&:display_name)
  end

  test "removing the second to last person is refused, because two is the minimum" do
    split = create_split(amount: "100", people_count: 2)

    assert_no_difference -> { split.participants.count } do
      delete split_participant_url(split, split.participants.first), as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_match "at least 2 people", response.body
  end

  # Naming.

  test "naming a row puts a saved person on it" do
    split = create_split(amount: "100", people_count: 2)
    person = Person.create!(name: "Marissa", owner_token: split.owner_token)
    participant = split.participants.first

    patch split_participant_url(split, participant),
          params: { participant: { person_id: person.id } }, as: :turbo_stream

    assert_response :success
    assert_equal person, participant.reload.person
    assert_equal "Marissa", participant.display_name
  end

  test "naming a row leaves the amounts alone" do
    split = create_split(amount: "100", people_count: 3)
    person = Person.create!(name: "Marissa", owner_token: split.owner_token)

    patch split_participant_url(split, split.participants.first),
          params: { participant: { person_id: person.id } }, as: :turbo_stream

    assert_equal [ 3334, 3333, 3333 ], split.reload.participants.map(&:amount_cents)
  end

  test "clearing the name puts the placeholder back" do
    split = create_split(amount: "100", people_count: 2)
    person = Person.create!(name: "Marissa", owner_token: split.owner_token)
    participant = split.participants.first
    participant.update!(person: person)

    patch split_participant_url(split, participant),
          params: { participant: { person_id: "" } }, as: :turbo_stream

    assert_nil participant.reload.person
    assert_equal "Person 1", participant.display_name
  end

  test "another browser's saved person cannot be stapled onto this split" do
    split = create_split(amount: "100", people_count: 2)
    participant = split.participants.first

    patch split_participant_url(split, participant),
          params: { participant: { person_id: people(:marissa).id } }, as: :turbo_stream

    assert_response :not_found
    assert_nil participant.reload.person
  end

  # Ownership.

  test "a different browser cannot add a row to someone else's split" do
    stranger = splits(:stranger_brunch)

    assert_no_difference -> { stranger.participants.count } do
      post split_participants_url(stranger), as: :turbo_stream
    end

    assert_response :not_found
  end

  test "a different browser cannot remove a row from someone else's split" do
    stranger = splits(:stranger_brunch)

    assert_no_difference -> { stranger.participants.count } do
      delete split_participant_url(stranger, stranger.participants.first), as: :turbo_stream
    end

    assert_response :not_found
  end
end
