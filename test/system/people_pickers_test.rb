require "application_system_test_case"

# The people picker is the Connect sheet on each row: search the saved contacts,
# create one on the spot, or tap a recent friend. Saving a split is what makes
# a contact "saved", so these tests save one first.
class PeoplePickersTest < ApplicationSystemTestCase
  test "a connected person is saved for next time" do
    save_split_with "Marissa"

    click_on "New split"
    enter_bill_amount("100")
    start_group
    click_on "Add person", exact: true
    click_on "Connect Person 1"

    within "dialog[open]" do
      assert_button "Choose Marissa"
      fill_in "Name", with: "mar"
      assert_selector "[role=option]", text: "Marissa"
    end
  end

  test "results narrow as you type" do
    save_split_with "Marissa", "Dana"

    open_connect_sheet_on_a_new_split
    fill_in "Name", with: "mar"

    assert_selector "[role=option]", text: "Marissa"
    assert_no_selector "[role=option]", text: "Dana"

    fill_in "Name", with: "da"

    assert_selector "[role=option]", text: "Dana"
    assert_no_selector "[role=option]", text: "Marissa"
  end

  test "a search with no match says so and offers to create the contact" do
    save_split_with "Marissa"

    open_connect_sheet_on_a_new_split
    fill_in "Name", with: "Zoe"

    assert_text "No matching contacts"
    assert_selector "[role=option]", text: "Create contact “Zoe”"
  end

  test "a name that is typed but never chosen cannot be connected" do
    open_connect_sheet_on_a_new_split
    fill_in "Name", with: "Zoe"
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true

    assert_text "Choose a contact or create one from the search."
  end

  test "cancelling the picker puts the row back" do
    open_connect_sheet_on_a_new_split

    click_on "Close connection"

    assert_no_selector "dialog[open]"
    assert_button "Connect Person 1"
  end

  test "a recent friend fills the selected seat without increasing the group" do
    save_split_with "Alex Rivera"

    click_on "New split"
    enter_bill_amount("90")
    fill_in "What's this for?", with: "Dinner"
    start_group
    2.times { click_on "Add person", exact: true }
    click_on "Connect Person 2"
    click_on "Choose Alex Rivera"
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true
    assert_selector "[data-share-row-name]", text: "Alex Rivera"

    save_split_and_open_editor

    assert_button "Connect Alex Rivera"
    assert_field "What's this for?", with: "Dinner", readonly: true
    assert_equal [ "$45", "$45" ], share_amounts
  end

  test "the same contact cannot sit in two seats" do
    save_split_with "Alex Rivera"

    click_on "New split"
    enter_bill_amount("90")
    start_group
    2.times { click_on "Add person", exact: true }
    click_on "Connect Person 1"
    click_on "Choose Alex Rivera"
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true

    click_on "Connect Person 2"

    assert_button "Choose Alex Rivera", disabled: true
  end

  private

  # Makes a split in the browser so these people become saved contacts, and
  # leaves the browser on its requests screen.
  def save_split_with(*names)
    visit root_path
    enter_bill_amount("100")
    set_people_count(names.size)
    names.each_with_index { |name, index| connect_person("Person #{index + 1}", name) }
    click_on "Next"
    click_on "Save split"
    assert_selector "h1", text: "Send requests"
  end

  def open_connect_sheet_on_a_new_split
    visit root_path
    enter_bill_amount("100")
    start_group
    click_on "Add person", exact: true
    click_on "Connect Person 1"
    assert_selector "dialog[open]"
  end
end
