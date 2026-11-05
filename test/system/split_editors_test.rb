require "application_system_test_case"

# Editing a saved split reopens the same composer the split was made in, already
# on the people step, so these tests are about what survives the round trip.
class SplitEditorsTest < ApplicationSystemTestCase
  test "saving a quick split opens requests and the editor keeps the calculated shares" do
    open_editor_for "100", 3

    assert_selector "h1", text: "Edit split"
    assert_field "What's this for?", with: "Dinner", readonly: true
    assert_field "Amount", with: "100.00", readonly: true
    assert_equal [ "$33.34", "$33.33", "$33.33" ], share_amounts
    assert_text "You pay\n$0"
  end

  test "the editor renames a split" do
    open_editor_for "100", 3

    edit_bill_details(title: "Dinner at Rosalia")
    save_from_the_people_step

    assert_text "Saved."
    assert_text "Dinner at Rosalia"
    click_on "Edit split"
    assert_field "What's this for?", with: "Dinner at Rosalia", readonly: true
  end

  # Rows that were never set by hand are not locked, so a new total only needs
  # "Split evenly" to hand every row its new share. Until then the editor says
  # the old shares are over the bill rather than quietly rewriting them.
  test "changing the total respreads the shares once they are split evenly again" do
    open_editor_for "100", 3

    edit_bill_details(amount: "90")
    assert_text "Over the bill by"
    assert_button "Next", disabled: true

    click_on "Split evenly"
    assert_equal [ "$30", "$30", "$30" ], share_amounts
    save_from_the_people_step

    assert_selector "#requests .request-amount", text: "$30.00", count: 3
  end

  test "a total that leaves somebody nothing is refused and nothing is saved" do
    split = nil
    open_editor_for "100", 3
    split = Split.find(current_url[%r{/splits/(\d+)}, 1])

    edit_bill_details(amount: "0.02")
    click_on "Split evenly"
    click_on "Next"
    click_on "Save split"

    # The draft refuses to leave the browser, so the page stays on the editor.
    assert_current_path edit_split_path(split)

    # What matters is that none of it reached the database.
    visit edit_split_path(split)

    assert_field "Amount", with: "100.00", readonly: true
    # Waits for the page to draw the rows; reading them straight away can catch
    # the composer half-rendered.
    assert_selector "[data-share-row-amount]", text: "$33.34", count: 1
    assert_selector "[data-share-row-amount]", text: "$33.33", count: 2
  end

  test "finishing the editor saves changes before opening requests" do
    open_editor_for "100", 3

    edit_bill_details(title: "Lunch together", amount: "90")
    click_on "Split evenly"
    save_from_the_people_step

    assert_selector "h1", text: "Send requests"
    assert_text "Lunch together"
    assert_selector "#requests .request-amount", text: "$30.00", count: 3
    click_on "Edit split"
    assert_field "Amount", with: "90.00", readonly: true
  end

  test "review shows who pays what before anything is saved" do
    open_editor_for "100", 3

    click_on "Next"

    assert_selector "h2", text: "Review"
    assert_selector ".review-list li", count: 3
    assert_text "You pay\n$0"

    click_on "Back to people"
    assert_selector "h2", text: "Your group"
  end

  private

  def save_from_the_people_step
    click_on "Next"
    click_on "Save split"
    assert_selector "h1", text: /Send requests|All settled/
  end
end
