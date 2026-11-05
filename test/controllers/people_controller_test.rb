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

  # Payment handles on a saved person.

  test "a saved person can be given the handles to ask them for money at" do
    split = create_split(amount: "100", people_count: 2)
    person = save_people(split, "Marissa").first

    patch person_url(person), params: { person: {
      venmo_handle: "@marissa-v", cashapp_cashtag: "$marissa", zelle_contact: "m@example.com"
    } }, as: :turbo_stream

    assert_response :success
    person.reload

    assert_equal "marissa-v", person.venmo_handle
    assert_equal "marissa", person.cashapp_cashtag
    assert_equal "m@example.com", person.zelle_contact
  end

  test "the handle form answers inside that person's own frame" do
    split = create_split(amount: "100", people_count: 2)
    person = save_people(split, "Marissa").first

    get edit_person_url(person)

    assert_response :success
    assert_select "turbo-frame##{ActionView::RecordIdentifier.dom_id(person, :payment)}"
  end

  test "a bad handle is refused and the person is left alone" do
    split = create_split(amount: "100", people_count: 2)
    person = save_people(split, "Marissa").first

    patch person_url(person), params: { person: { venmo_handle: "not a username" } },
                              as: :turbo_stream

    assert_response :unprocessable_entity
    assert_nil person.reload.venmo_handle
  end

  # The handle form must not become a back door for renaming somebody.
  test "the handle form cannot rename a person" do
    split = create_split(amount: "100", people_count: 2)
    person = save_people(split, "Marissa").first

    patch person_url(person), params: { person: { name: "Someone else", venmo_handle: "m" } },
                              as: :turbo_stream

    assert_equal "Marissa", person.reload.name
    assert_equal "m", person.venmo_handle
  end

  test "another browser's person cannot be given handles" do
    patch person_url(people(:marissa)), params: { person: { venmo_handle: "mine" } },
                                        as: :turbo_stream

    assert_response :not_found
    assert_nil people(:marissa).reload.venmo_handle
  end

  private

  # Saved under the split's own owner_token, which is this test browser's cookie
  # value — the fixtures belong to other browsers on purpose.
  def save_people(split, *names)
    names.map { |name| Person.create!(name: name, owner_token: split.owner_token) }
  end
end
