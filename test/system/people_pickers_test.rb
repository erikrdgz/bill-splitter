require "application_system_test_case"

class PeoplePickersTest < ApplicationSystemTestCase
  test "a placeholder row becomes a saved name, and the name is there next time" do
    open_editor_for "100", 3

    click_on "Name Person 1"
    fill_in "Find a name", with: "Marissa"
    click_on "Add “Marissa” as a new person"

    assert_link "Name Marissa"
    assert_no_link "Name Person 1"

    # Saved for next time: the second row can now find her by typing.
    click_on "Name Person 2"
    fill_in "Find a name", with: "mar"

    assert_button "Marissa"
  end

  test "results narrow as you type" do
    open_editor_for "100", 3
    save_name_on_row "Name Person 1", "Marissa"
    save_name_on_row "Name Person 2", "Dana"

    click_on "Name Person 3"
    fill_in "Find a name", with: "mar"

    assert_button "Marissa"
    assert_no_button "Dana"

    fill_in "Find a name", with: "da"

    assert_button "Dana"
    assert_no_button "Marissa"
  end

  test "picking a saved name fills the row and leaves the amounts alone" do
    open_editor_for "100", 3
    save_name_on_row "Name Person 1", "Marissa"

    click_on "Name Person 2"
    fill_in "Find a name", with: "mar"
    # click_button, not click_on: row 1 is already a link reading "Marissa", and
    # the picker result is a button reading the same.
    click_button "Marissa"

    assert_link "Name Marissa", count: 2
    assert_row_amounts [ "$33.34", "$33.33", "$33.33" ]
  end

  test "a search with no match says so and offers to save the name" do
    open_editor_for "100", 3

    click_on "Name Person 1"
    fill_in "Find a name", with: "Zoe"

    assert_text "No saved name matches"
    assert_button "Add “Zoe” as a new person"
  end

  test "cancelling the picker puts the row back" do
    open_editor_for "100", 3

    click_on "Name Person 1"
    click_on "Cancel"

    assert_link "Name Person 1"
    assert_no_field "Find a name"
  end

  # Adding and removing rows, which move money in every other row.

  test "adding a person respreads the money without reloading the page" do
    open_editor_for "90", 2

    assert_row_amounts [ "$45.00", "$45.00" ]

    click_on "Add a person"

    # Wait for the Turbo Stream to land before reading: all() does not retry.
    assert_selector "ol#participants > li", count: 3

    assert_row_amounts [ "$30.00", "$30.00", "$30.00" ]
    assert_text "You pay\n$0.00"
  end

  test "removing a person respreads the money" do
    open_editor_for "90", 3

    find("ol#participants > li", text: "Person 3").send_keys(:delete)

    assert_selector "ol#participants > li", count: 2

    assert_row_amounts [ "$45.00", "$45.00" ]
  end

  test "the last saved person cannot be removed" do
    open_editor_for "90", 1

    assert_selector "button[aria-label='Remove Person 1'][disabled]", visible: :all
  end

  test "a recent friend fills the selected seat without increasing the group" do
    open_editor_for "100", 2
    save_name_on_row "Name Person 1", "Alex Rivera"
    within "#recent_friends" do
      assert_button "Alex Rivera is connected", disabled: true
    end
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
    assert_link "Name Alex Rivera"
    assert_field "What was it for?", with: "Dinner"
    assert_row_amounts [ "$45.00", "$45.00" ]
  end

  test "recent quick add appends a seat and preserves unsaved custom amounts" do
    open_editor_for "100", 2
    save_name_on_row "Name Person 1", "Alex Rivera"
    click_on "New split"
    enter_bill_amount("60")
    set_people_count(2)
    save_split_and_open_editor
    click_on "Custom"
    find("input[type=range]", match: :first).send_keys(:home)
    assert_row_amounts [ "$0.00", "$30.00" ]
    within "#recent_friends" do
      click_on "Connect Alex Rivera"
    end
    assert_link "Name Alex Rivera"
    assert_link "Name Person 1"
    assert_link "Name Person 2"
    assert_row_amounts [ "$0.00", "$30.00", "$0.00" ]
  end

  private

  def open_editor_for(amount, people_count)
    visit root_path
    enter_bill_amount(amount)
    set_people_count(people_count)
    save_split_and_open_editor
    assert_selector "h1", text: "Edit split"
  end

  def save_name_on_row(row_link, name)
    click_on row_link
    fill_in "Find a name", with: name
    click_on "Add “#{name}” as a new person"
    assert_link "Name #{name}"
  end
end
