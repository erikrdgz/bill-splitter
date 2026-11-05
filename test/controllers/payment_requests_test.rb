require "test_helper"

# The two sides of asking for money: the organizer's detail page, where they
# chase people, and the share page, where a friend settles up.
class PaymentRequestsTest < ActionDispatch::IntegrationTest
  # The organizer asking.

  test "a person with a phone gets a text link carrying a pay link to the organizer" do
    split = split_with_named_person(phone_number: "(555) 555-0101", method: "venmo")
    PaymentProfile.create!(owner_token: split.owner_token, venmo_handle: "erik-r")

    get split_url(split)

    assert_response :success
    assert_select "a[href^=?]", "sms:+15555550101?&body=" do |links|
      body = CGI.unescape(links.first["href"].split("&body=").last)

      assert_includes body, "Hi Marissa"
      assert_includes body, "$33.34"
      assert_includes body, "https://venmo.com/erik-r?"
      assert_includes body, "txn=pay"
    end
  end

  test "a Cash App request texts the organizer's cash.app link" do
    split = split_with_named_person(phone_number: "5555550101", method: "cash_app")
    PaymentProfile.create!(owner_token: split.owner_token, cashapp_cashtag: "erikr")

    get split_url(split)

    assert_select "a[href^='sms:']" do |links|
      assert_includes CGI.unescape(links.first["href"]), "https://cash.app/$erikr/33.34"
    end
  end

  test "a person with no phone number is offered the form to add one" do
    split = split_with_named_person(method: "venmo")
    PaymentProfile.create!(owner_token: split.owner_token, venmo_handle: "erik-r")

    get split_url(split)

    assert_select "a", text: "Add phone number"
    assert_select "a[href^='sms:']", count: 0
  end

  test "an organizer with no handle for the method is told, not given a dead button" do
    split = split_with_named_person(phone_number: "5555550101", method: "venmo")

    get split_url(split)

    assert_select "a[href^='sms:']", count: 0
    assert_select ".request-note", text: /Add your Venmo/
  end

  test "cash is arranged in person and never texted" do
    split = split_with_named_person(phone_number: "5555550101", method: "cash")

    get split_url(split)

    assert_select "a[href^='sms:']", count: 0
    assert_select ".cash-arrangement", text: /Paying in cash/
  end

  test "a row with no saved person is told what to do about it" do
    split = create_split(amount: "100", people_count: 2)

    get split_url(split)

    assert_select "#requests a", text: "Connect a friend", count: 2
  end

  test "the batch message holds unpaid shares and a link for friends to pay" do
    split = split_with_named_person(phone_number: "5555550101", method: "venmo")

    get split_url(split)

    assert_select "textarea[data-copy-logic-target=source]" do |fields|
      message = fields.first.text

      assert_match split.title, message
      assert_match "Marissa: $33.34", message
      assert_match share_url(split.share_token), message
      assert_match "Person 2: $33.33", message
    end
  end

  test "a fully paid split is not asked for money again" do
    split = split_with_named_person
    split.participants.each { |participant| participant.update!(paid_at: Time.current) }

    get split_url(split)

    assert_select "h1", text: "All settled"
    assert_select "#requests", count: 0
    assert_select "#participants > li", count: 3
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
  end

  test "a paid row is not offered a way to pay again" do
    split = create_split(amount: "100", people_count: 2)
    PaymentProfile.create!(owner_token: split.owner_token, venmo_handle: "erik-r")
    split.participants.first.update!(paid_at: Time.current)

    get share_url(split.share_token)

    assert_select "a[href^=?]", "https://venmo.com", count: 1
  end

  private

  def split_with_named_person(method: nil, **person_attributes)
    split = create_split(amount: "100", people_count: 3)
    person = Person.create!(name: "Marissa", owner_token: split.owner_token, **person_attributes)
    split.participants.first.update!(person: person, payment_method: method)
    split
  end
end
