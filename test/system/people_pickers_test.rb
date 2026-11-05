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
    assert_equal [ "$33.34", "$33.33", "$33.33" ], row_amounts
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

    assert_equal [ "$45.00", "$45.00" ], row_amounts

    click_on "Add a person"

    # Wait for the Turbo Stream to land before reading: all() does not retry.
    assert_selector "ol#participants > li", count: 3

    assert_equal [ "$30.00", "$30.00", "$30.00" ], row_amounts
    assert_text "Remaining\n$0.00"
  end

  test "removing a person respreads the money" do
    open_editor_for "90", 3

    accept_confirm { click_on "Remove Person 3" }

    assert_selector "ol#participants > li", count: 2

    assert_equal [ "$45.00", "$45.00" ], row_amounts
  end

  test "the last two people cannot be removed" do
    open_editor_for "90", 2

    assert_button "Remove Person 1", disabled: true
    assert_button "Remove Person 2", disabled: true
  end

  private

  def open_editor_for(amount, people_count)
    visit root_path
    fill_in "Amount", with: amount
    fill_in "People", with: people_count
    click_on "Save and add names"
    assert_selector "h1", text: "Edit split"
  end

  def save_name_on_row(row_link, name)
    click_on row_link
    fill_in "Find a name", with: name
    click_on "Add “#{name}” as a new person"
    assert_link "Name #{name}"
  end

  def row_amounts
    all("ol#participants > li .tabular-nums.font-medium").map(&:text)
  end
end
