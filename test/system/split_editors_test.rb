require "application_system_test_case"

class SplitEditorsTest < ApplicationSystemTestCase
  test "saving a quick split opens the editor with the shares already worked out" do
    visit root_path
    fill_in "Amount", with: "100"
    fill_in "People", with: "3"

    click_on "Save and add names"

    assert_selector "h1", text: "Edit split"
    assert_field "What was it for?", with: "Split on #{Date.current.strftime('%B %-d')}"
    assert_field "Total bill", with: "100.00"
    assert_row_amounts [ "$33.34", "$33.33", "$33.33" ]
    assert_text "You pay\n$0.00"
  end

  test "the editor renames a split" do
    open_editor_for "100", 3

    fill_in "What was it for?", with: "Dinner at Rosalia"
    click_on "Save name and total"

    assert_text "Saved."
    assert_field "What was it for?", with: "Dinner at Rosalia"
  end

  test "changing the total respreads the shares" do
    open_editor_for "100", 3

    fill_in "Total bill", with: "90"
    click_on "Save name and total"

    # Wait for the saved page before reading the rows: all() does not retry, so
    # reading straight after the click can catch the page Turbo is replacing.
    assert_text "Saved."

    assert_row_amounts [ "$30.00", "$30.00", "$30.00" ]
  end

  test "a total that leaves somebody nothing is refused and nothing is saved" do
    editor_url = open_editor_for "100", 3

    fill_in "Total bill", with: "0.02"
    click_on "Save name and total"

    assert_text "must be at least one cent per person"
    # The rejected page shows what would have been saved, so the organizer can
    # see why two cents between three people is not allowed.
    assert_field "Total bill", with: "0.02"

    # What matters is that none of it reached the database.
    visit editor_url

    assert_field "Total bill", with: "100.00"
    assert_row_amounts [ "$33.34", "$33.33", "$33.33" ]
  end

  private

  def open_editor_for(amount, people_count)
    visit root_path
    fill_in "Amount", with: amount
    fill_in "People", with: people_count
    click_on "Save and add names"
    assert_selector "h1", text: "Edit split"

    current_url
  end
end
