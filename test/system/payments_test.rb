require "application_system_test_case"

class PaymentsTest < ApplicationSystemTestCase
  test "the organizer saves how they get paid and friends can then pay them" do
    split = open_split_detail_with_venmo_and_cash_app_friends

    click_on "Add how you get paid"
    fill_in "Venmo username", with: "@erik-r"
    fill_in "Cash App $Cashtag", with: "$erikr"
    click_on "Save"

    # The frame comes back showing what was saved, without leaving the page.
    assert_text "Friends can pay you at Venmo erik-r and Cash App erikr."

    # The friend's side of the same split.
    visit share_path(split.share_token)

    assert_link "Pay with Venmo"
    assert_link "Pay with Cash App"
  end

  test "a bad handle is refused without losing the rest of the form" do
    open_split_detail

    click_on "Add how you get paid"
    fill_in "Venmo username", with: "not a username"
    click_on "Save"

    assert_text "is not a Venmo username"
    assert_field "Venmo username", with: "not a username"
  end

  test "cancelling the handle form puts the page back as it was" do
    open_split_detail

    click_on "Add how you get paid"
    click_on "Cancel"

    assert_link "Add how you get paid"
    assert_no_field "Venmo username"
  end

  test "a friend connected with a phone number can be texted, and the number can change" do
    open_split_detail_with_named_person
    save_organizer_venmo

    link = find("#requests a.payment-action", text: "Text Venmo link to Marissa")
    assert link[:href].start_with?("sms:+15555550101?&body=")

    within "#requests" do
      click_on "Change phone number"
    end
    fill_in "Phone number", with: "(555) 555-0102"
    click_on "Save"

    assert_link "Change phone number"
    link = find("#requests a.payment-action", text: "Text Venmo link to Marissa")
    assert link[:href].start_with?("sms:+15555550102?&body=")
  end

  test "a bad phone number is refused without losing what was typed" do
    open_split_detail_with_named_person
    save_organizer_venmo

    within "#requests" do
      click_on "Change phone number"
    end
    fill_in "Phone number", with: "call me"
    click_on "Save"

    assert_text "is not a phone number"
    assert_field "Phone number", with: "call me"
  end

  test "nothing is offered for an app the organizer cannot be paid on" do
    open_split_detail_with_named_person

    within "#requests" do
      assert_no_text "Zelle"
      assert_no_text "Apple Pay"
      assert_no_text "demo"
      assert_no_selector "a[href^='sms:']"
    end
  end

  test "the whole set of requests copies as one message" do
    open_split_detail_with_named_person

    find("summary", text: "View group message").click
    click_on "Copy the message"

    # Either the clipboard worked or the page said how to copy by hand. It never
    # claims a copy that did not happen.
    assert_selector "[role=status]", text: /copied|text to copy/i
  end

  # There is no system share sheet: each request is sent from its own Text
  # button, and "Share requests" copies the group message and shows a recap.
  test "sharing the requests shows a recap and Close goes home" do
    split = open_split_detail

    click_on "Share requests"

    assert_selector ".shared-screen h2", text: "Shared!"
    assert_selector ".shared-recap", text: /Total\s+\$100\.00/
    assert_selector ".shared-recap", text: /Requested from\s+3 people/
    assert_selector ".shared-recap", text: /Still owed\s+\$100\.00/
    assert_not split.reload.fully_paid?

    click_on "Close"

    assert_selector "h1", text: "Split a bill"
  end

  test "the group message carries the link friends use to pay" do
    split = open_split_detail

    find("summary", text: "View group message").click

    assert_field "Every request as one message", with: /#{Regexp.escape(share_path(split.share_token))}/
  end

  private

  def save_organizer_venmo
    click_on "Add how you get paid"
    fill_in "Venmo username", with: "erik-r"
    click_on "Save"
    assert_text "Friends can pay you at Venmo erik-r"
  end

  # Every row has to be connected before a split can be saved, so the requests
  # screen only ever sees people with a way to pay.
  def open_split_detail
    visit root_path
    enter_bill_amount("100")
    set_people_count("3")
    save_split

    Split.find(current_url[%r{/splits/(\d+)}, 1])
  end

  def open_split_detail_with_named_person
    visit root_path
    enter_bill_amount("100")
    set_people_count("3")
    connect_person("Person 1", "Marissa", method: "venmo", phone: "(555) 555-0101")
    save_split
  end

  # A friend is only offered the app they said they would pay with, so showing
  # both of the organizer's handles takes one friend on each.
  def open_split_detail_with_venmo_and_cash_app_friends
    visit root_path
    enter_bill_amount("100")
    set_people_count("3")
    connect_person("Person 1", "Marissa", method: "venmo", phone: "(555) 555-0101")
    connect_person("Person 2", "Dana", method: "cash_app", phone: "(555) 555-0102")
    save_split

    Split.find(current_url[%r{/splits/(\d+)}, 1])
  end
end
