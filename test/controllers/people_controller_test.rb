require "test_helper"

class PeopleControllerTest < ActionDispatch::IntegrationTest
  test "opening the picker answers inside that row's name frame" do
    split = create_split(amount: "100", people_count: 2)
    participant = split.participants.first

    get people_url(participant_id: participant.id)

    assert_response :success
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(participant, :name)}"
    assert_select "turbo-frame#people_results"
    assert_select "input[name=?]", "query"
  end

  test "a browser with no saved names is told so, rather than shown an empty box" do
    split = create_split(amount: "100", people_count: 2)

    get people_url(participant_id: split.participants.first.id)

    assert_select "turbo-frame#people_results", text: /No saved names yet/
  end

  test "searching narrows to matching saved names" do
    split = create_split(amount: "100", people_count: 2)
    save_people(split, "Marissa", "Marcus", "Dana")

    get people_url(participant_id: split.participants.first.id, query: "ma")

    assert_select "turbo-frame#people_results" do
      assert_select "li", 2
      assert_select "input[type=submit][value=?]", "Marissa"
      assert_select "input[type=submit][value=?]", "Marcus"
    end
  end

  test "a search matching nothing offers to save the name instead" do
    split = create_split(amount: "100", people_count: 2)
    save_people(split, "Marissa")

    get people_url(participant_id: split.participants.first.id, query: "Zoe")

    assert_select "turbo-frame#people_results", text: /No saved name matches/
    assert_select "input[type=submit][value=?]", "Add “Zoe” as a new person"
  end

  # Offering to save a name that already exists would just fail validation.
  test "a search matching a saved name exactly does not offer to save it again" do
    split = create_split(amount: "100", people_count: 2)
    save_people(split, "Marissa")

    get people_url(participant_id: split.participants.first.id, query: "marissa")

    assert_select "input[type=submit][value=?]", "Add “marissa” as a new person", count: 0
  end

  test "a search sees only this browser's saved names" do
    split = create_split(amount: "100", people_count: 2)

    # The fixtures hold a "Marissa" saved by a different browser.
    get people_url(participant_id: split.participants.first.id, query: "Marissa")

    assert_select "turbo-frame#people_results", text: /No saved name matches/
  end

  # Adding a new name.

  test "adding a new name saves it and puts it on the row in one request" do
    split = create_split(amount: "100", people_count: 2)
    participant = split.participants.first

    assert_difference -> { Person.count }, 1 do
      post people_url, params: { participant_id: participant.id, person: { name: "Zoe" } },
                       as: :turbo_stream
    end

    assert_response :success
    assert_equal "Zoe", participant.reload.display_name
    assert_equal split.owner_token, Person.find_by(name: "Zoe").owner_token
  end

  test "a name saved on the spot is there for the next split" do
    split = create_split(amount: "100", people_count: 2)
    post people_url, params: { participant_id: split.participants.first.id,
                               person: { name: "Zoe" } }, as: :turbo_stream

    get people_url(participant_id: split.participants.second.id, query: "zo")

    assert_select "input[type=submit][value=?]", "Zoe"
  end

  test "a duplicate name is refused and the picker stays open" do
    split = create_split(amount: "100", people_count: 2)
    save_people(split, "Marissa")

    assert_no_difference -> { Person.count } do
      post people_url, params: { participant_id: split.participants.first.id,
                                 person: { name: "marissa" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /already been taken/
  end

  test "a blank name is refused" do
    split = create_split(amount: "100", people_count: 2)

    assert_no_difference -> { Person.count } do
      post people_url, params: { participant_id: split.participants.first.id,
                                 person: { name: "" } }, as: :turbo_stream
    end

    assert_response :unprocessable_entity
  end

  # Ownership.

  test "the picker cannot be pointed at another browser's row" do
    get people_url(participant_id: participants(:stranger_one).id)

    assert_response :not_found
  end

  test "a name cannot be added to another browser's row" do
    assert_no_difference -> { Person.count } do
      post people_url, params: { participant_id: participants(:stranger_one).id,
                                 person: { name: "Zoe" } }, as: :turbo_stream
    end

    assert_response :not_found
  end

  private

  # Saved under the split's own owner_token, which is this test browser's cookie
  # value — the fixtures belong to other browsers on purpose.
  def save_people(split, *names)
    names.map { |name| Person.create!(name: name, owner_token: split.owner_token) }
  end
end
