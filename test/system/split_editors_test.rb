require "application_system_test_case"

class SplitEditorsTest < ApplicationSystemTestCase
  test "saving a quick split opens the editor with the shares already worked out" do
    visit root_path
    fill_in "Amount", with: "100"
    fill_in "People", with: "3"

    click_on "Save and add names"

    assert_selector "h1", text: "Edit split"
    assert_field "Title", with: "Split on #{Date.current.strftime('%B %-d')}"
    assert_field "Total", with: "100.00"
    assert_equal [ "$33.34", "$33.33", "$33.33" ], row_amounts
    assert_text "Remaining\n$0.00"
  end

  test "the editor renames a split" do
    open_editor_for "100", 3

    fill_in "Title", with: "Dinner at Rosalia"
    click_on "Save"

    assert_text "Saved."
    assert_field "Title", with: "Dinner at Rosalia"
  end

  test "changing the total respreads the shares" do
    open_editor_for "100", 3

    fill_in "Total", with: "90"
    click_on "Save"

    # Wait for the saved page before reading the rows: all() does not retry, so
    # reading straight after the click can catch the page Turbo is replacing.
    assert_text "Saved."

    assert_equal [ "$30.00", "$30.00", "$30.00" ], row_amounts
  end

  test "a total that leaves somebody nothing is refused and nothing is saved" do
    editor_url = open_editor_for "100", 3

    fill_in "Total", with: "0.02"
    click_on "Save"

    assert_text "must be at least one cent per person"
    # The rejected page shows what would have been saved, so the organizer can
    # see why two cents between three people is not allowed.
    assert_field "Total", with: "0.02"

    # What matters is that none of it reached the database.
    visit editor_url

    assert_field "Total", with: "100.00"
    assert_equal [ "$33.34", "$33.33", "$33.33" ], row_amounts
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

  def row_amounts
    all("ol#participants > li .tabular-nums.font-medium").map(&:text)
  end
end
