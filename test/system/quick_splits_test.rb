require "application_system_test_case"

# The quick split's whole promise is that the numbers move as you type, with no
# request in between. That cannot be proved by a controller test, because there
# is no second request to assert on — so these drive a real browser.
class QuickSplitsTest < ApplicationSystemTestCase
  test "no amount yet means no figures" do
    visit root_path

    assert_equal [ "—", "—" ], share_amounts
    assert_no_text "one cent more"
  end

  test "shares appear as the amount is typed, with no save in between" do
    visit root_path

    fill_in "Amount", with: "100"

    assert_equal [ "$50.00", "$50.00" ], share_amounts
  end

  # The spec's headline example.
  test "a hundred dollars between three people is 33.34, 33.33, 33.33" do
    visit root_path

    fill_in "Amount", with: "100"
    fill_in "People", with: "3"

    assert_equal [ "$33.34", "$33.33", "$33.33" ], share_amounts
    assert_text "Person 1 pays one cent more, so the shares add up to $100.00."
  end

  test "the shares always add up to the amount, cents and all" do
    visit root_path

    fill_in "Amount", with: "100.01"
    fill_in "People", with: "3"

    assert_equal [ "$33.34", "$33.34", "$33.33" ], share_amounts
    assert_text "The first 2 people each pay one cent more"
  end

  test "an amount that divides cleanly says nothing about cents" do
    visit root_path

    fill_in "Amount", with: "90"
    fill_in "People", with: "3"

    assert_equal [ "$30.00", "$30.00", "$30.00" ], share_amounts
    assert_no_text "one cent more"
  end

  test "the stepper adds and removes rows" do
    visit root_path
    fill_in "Amount", with: "60"

    click_on "One more person"

    assert_equal [ "$20.00", "$20.00", "$20.00" ], share_amounts

    click_on "One fewer person"

    assert_equal [ "$30.00", "$30.00" ], share_amounts
  end

  test "the stepper stops at two people" do
    visit root_path

    assert_button "One fewer person", disabled: true
    assert_equal 2, share_amounts.size
  end

  test "the stepper stops at twenty people" do
    visit root_path
    fill_in "Amount", with: "100"

    fill_in "People", with: "19"
    click_on "One more person"

    assert_equal 20, share_amounts.size
    assert_button "One more person", disabled: true
  end

  # Typing is allowed to be mid-thought, so an out-of-range number is used for
  # the math straight away but only corrected in the field once committed.
  test "a typed head count above the maximum is clamped" do
    visit root_path
    fill_in "Amount", with: "100"

    fill_in "People", with: "50"

    assert_equal 20, share_amounts.size

    find_field("People").send_keys(:tab)

    assert_field "People", with: "20"
  end

  test "letters typed into the amount are ignored rather than breaking the math" do
    visit root_path
    fill_in "Amount", with: "1oo"

    assert_equal [ "$0.50", "$0.50" ], share_amounts
  end

  private

  # Only the live rows, never the <template> beside them: a real browser keeps
  # template content out of the document, so this selector cannot see it.
  def share_amounts
    all("ol[data-quick-split-logic-target='shares'] > li [data-share-row-amount]").map(&:text)
  end
end
