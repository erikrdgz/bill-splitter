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

    assert_link "Venmo →"
    assert_link "Cash App →"
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

  test "the organizer gives a friend a handle and can then request from them" do
    open_split_detail_with_named_person

    within "#requests" do
      click_on "Add payment details"
    end
    fill_in "Venmo username", with: "marissa-v"
    click_on "Save"

    assert_text "Venmo marissa-v"
    assert_link "Venmo →"
  end

  # Nothing is dressed up as working when it is not.
  test "an app that cannot really request says so when opened" do
    open_split_detail_with_named_person

    within "#requests" do
      click_on "Add payment details"
    end
    fill_in "Cash App $Cashtag", with: "marissa"
    click_on "Save"

    assert_text "Cash App (demo)"

    find("summary", text: "Cash App").click

    assert_text "Nothing has been sent."
    assert_text "cannot ask for it"
  end

  # Apple Pay belongs to the device, not to a handle, so it is always on offer —
  # and always honest about being a demonstration.
  test "apps nobody has a handle for are not shown as dead controls" do
    open_split_detail_with_named_person

    within "#requests" do
      click_on "Add payment details"
    end
    fill_in "Venmo username", with: "marissa-v"
    click_on "Save"

    within "#requests" do
      assert_link "Venmo →"
      assert_no_text "Cash App"
      assert_no_text "Zelle"
      assert_text "Apple Pay (demo)"
    end
  end

  test "a row with nobody named says what to do about it" do
    open_split_detail

    assert_text "Name this row in the editor and you can ask them here."
  end

  test "the whole set of requests copies as one message" do
    open_split_detail_with_named_person

    click_on "Copy the message"

    # Either the clipboard worked or the page said how to copy by hand. It never
    # claims a copy that did not happen.
    assert_selector "[role=status]", text: /copied|⌘C/i
  end

  private

  def open_split_detail
    visit root_path
    fill_in "Amount", with: "100"
    fill_in "People", with: "3"
    click_on "Save and add names"
    assert_selector "h1", text: "Edit split"

    click_on "Share and request money"
    assert_selector "h2", text: "Share this split"

    Split.find(current_url[%r{/splits/(\d+)}, 1])
  end

  def open_split_detail_with_named_person
    visit root_path
    fill_in "Amount", with: "100"
    fill_in "People", with: "3"
    click_on "Save and add names"
    assert_selector "h1", text: "Edit split"

    click_on "Name Person 1"
    fill_in "Find a name", with: "Marissa"
    click_on "Add “Marissa” as a new person"
    assert_link "Name Marissa"

    click_on "Share and request money"
    assert_selector "h2", text: "Ask for the money"
  end
end
