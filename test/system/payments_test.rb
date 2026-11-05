require "application_system_test_case"

class PaymentsTest < ApplicationSystemTestCase
  test "the organizer saves how they get paid and friends can then pay them" do
    split = open_split_detail

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

  test "the organizer gives a friend a phone number and can then text them" do
    open_split_detail_with_named_person
    save_organizer_venmo

    within "#requests" do
      click_on "Add phone number"
    end
    fill_in "Phone number", with: "(555) 555-0101"
    click_on "Save"

    assert_link "Change phone number"
    link = find("#requests a.payment-action", text: "Text Venmo link to Marissa")
    assert link[:href].start_with?("sms:+15555550101?&body=")
  end

  test "a bad phone number is refused without losing what was typed" do
    open_split_detail_with_named_person

    within "#requests" do
      click_on "Add phone number"
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

  test "a row with nobody named says what to do about it" do
    open_split_detail

    assert_selector "#requests a", text: "Connect a friend", count: 3
  end

  test "the whole set of requests copies as one message" do
    open_split_detail_with_named_person

    find("summary", text: "View group message").click
    click_on "Copy the message"

    # Either the clipboard worked or the page said how to copy by hand. It never
    # claims a copy that did not happen.
    assert_selector "[role=status]", text: /copied|text to copy/i
  end

  test "sharing uses the device share sheet with the payer link" do
    split = open_split_detail
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "share", { configurable: true, value: async (data) => {
        document.body.dataset.sharedMessage = data.text
      } })
    JS
    click_on "Share requests"
    assert_eventually { page.evaluate_script("document.body.dataset.sharedMessage").to_s.include?(share_path(split.share_token)) }
    assert_selector "#requests > li", count: 3
    assert_no_text "Message copied."
    assert_not split.reload.fully_paid?
  end

  test "canceling the share sheet leaves requests unchanged" do
    open_split_detail
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "share", { configurable: true, value: async () => {
        throw new DOMException("Canceled", "AbortError")
      } })
    JS
    click_on "Share requests"
    assert_selector "#requests > li", count: 3
    assert_no_selector ".message-preview[open]"
    assert_no_text "Message copied."
  end

  test "sharing falls back to a readable message when native sharing fails" do
    split = open_split_detail
    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "share", { configurable: true, value: async () => {
        throw new Error("Unavailable")
      } })
    JS
    click_on "Share requests"
    assert_selector ".message-preview[open]"
    assert_field "Every request as one message", with: /#{Regexp.escape(share_path(split.share_token))}/
    assert_selector "[role=status]", text: /copied|text to copy/i
  end

  private

  def save_organizer_venmo
    click_on "Add how you get paid"
    fill_in "Venmo username", with: "erik-r"
    click_on "Save"
    assert_text "Friends can pay you at Venmo erik-r"
  end

  def open_split_detail
    visit root_path
    enter_bill_amount("100")
    set_people_count("3")
    save_split_and_open_editor
    assert_selector "h1", text: "Edit split"

    click_on "Save and view requests"
    assert_selector "h1", text: "Send requests"

    Split.find(current_url[%r{/splits/(\d+)}, 1])
  end

  def open_split_detail_with_named_person
    visit root_path
    enter_bill_amount("100")
    set_people_count("3")
    save_split_and_open_editor
    assert_selector "h1", text: "Edit split"

    click_on "Name Person 1"
    fill_in "Find a name", with: "Marissa"
    click_on "Add “Marissa” as a new person"
    assert_link "Name Marissa"

    click_on "Save and view requests"
    assert_selector "h1", text: "Send requests"
  end
end
