require "test_helper"

# The two sides of asking for money: the organizer's detail page, where they
# chase people, and the share page, where a friend settles up.
class PaymentRequestsTest < ActionDispatch::IntegrationTest
  # The organizer asking.

  test "the detail page offers a real Venmo request for a person who has one" do
    split = split_with_named_person(venmo_handle: "marissa-v")

    get split_url(split)

    assert_response :success
    assert_select "a[href^=?]", "https://venmo.com/marissa-v?" do |links|
      query = URI.decode_www_form(URI.parse(links.first["href"]).query).to_h

      assert_equal "charge", query["txn"]
      assert_equal "33.34", query["amount"]
      assert_equal split.title, query["note"]
    end
  end

  # Cash App can send money but not ask for it, so the organizer's side shows it
  # as a demonstration rather than a dead link.
  test "apps that cannot really request say so instead of pretending" do
    split = split_with_named_person(cashapp_cashtag: "marissa")

    get split_url(split)

    assert_select "details", text: /Cash App/
    assert_select "details", text: /Nothing has been sent/
  end

  test "a row with no saved person is told what to do about it" do
    split = create_split(amount: "100", people_count: 2)

    get split_url(split)

    assert_select "li", text: /Name this row in the editor/
  end

  test "a named person with no handles is offered the form to add them" do
    split = split_with_named_person

    get split_url(split)

    assert_select "a", text: "Add payment details"
  end

  test "the batch message holds every unpaid share and the links that are real" do
    split = split_with_named_person(venmo_handle: "marissa-v")

    get split_url(split)

    assert_select "textarea[data-copy-logic-target=source]" do |fields|
      message = fields.first.text

      assert_match split.title, message
      assert_match "Marissa: $33.34", message
      assert_match "https://venmo.com/marissa-v", message
      assert_match "Person 2: $33.33", message
    end
  end

  test "a fully paid split is not asked for money again" do
    split = split_with_named_person(venmo_handle: "marissa-v")
    split.participants.each { |participant| participant.update!(paid_at: Time.current) }

    get split_url(split)

    assert_select "h2", text: "Ask for the money", count: 0
  end

  # The friend paying.

  test "the share page offers real pay links using the organizer's handles" do
    split = create_split(amount: "100", people_count: 2)
    PaymentProfile.create!(owner_token: split.owner_token, venmo_handle: "erik-r",
                           cashapp_cashtag: "erikr")

    get share_url(split.share_token)

    assert_select "a[href^=?]", "https://venmo.com/erik-r?"
    assert_select "a[href=?]", "https://cash.app/$erikr/50.00"
  end

  test "the share page asks for nothing when the organizer has not said how" do
    split = create_split(amount: "100", people_count: 2)

    get share_url(split.share_token)

    assert_response :success
    assert_select "a[href^=?]", "https://venmo.com", count: 0
    assert_select "details", count: 0
  end

  test "a paid row is not offered a way to pay again" do
    split = create_split(amount: "100", people_count: 2)
    PaymentProfile.create!(owner_token: split.owner_token, venmo_handle: "erik-r")
    split.participants.first.update!(paid_at: Time.current)

    get share_url(split.share_token)

    assert_select "a[href^=?]", "https://venmo.com", count: 1
  end

  private

  def split_with_named_person(**handles)
    split = create_split(amount: "100", people_count: 3)
    person = Person.create!(name: "Marissa", owner_token: split.owner_token, **handles)
    split.participants.first.update!(person: person)
    split
  end
end
