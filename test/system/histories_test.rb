require "application_system_test_case"

class HistoriesTest < ApplicationSystemTestCase
  test "an empty history invites starting a split" do
    visit splits_path

    assert_text "Nothing here yet."
    assert_link "Split a bill"

    click_on "Split a bill"

    assert_selector "h1", text: "Split a bill"
  end

  test "a saved split turns up in history with its total and what is owed" do
    save_split_called "Dinner at Rosalia", amount: "100", people_count: 3

    visit splits_path

    assert_selector "#splits > li", count: 1
    assert_text "Dinner at Rosalia"
    assert_text "$100.00"
    assert_text "$100.00 owed"
  end

  test "splits are listed newest first" do
    save_split_called "Taxi home", amount: "45", people_count: 2
    save_split_called "Dinner at Rosalia", amount: "100", people_count: 3

    visit splits_path

    assert_selector "#splits > li:first-child", text: "Dinner at Rosalia"
    assert_selector "#splits > li:last-child", text: "Taxi home"
  end

  test "tapping a split opens its detail page" do
    save_split_called "Dinner at Rosalia", amount: "100", people_count: 3

    visit splits_path
    click_on "Dinner at Rosalia"

    assert_selector "h1", text: "Dinner at Rosalia"
    assert_selector "h2", text: "Who has paid"
  end

  test "history is reachable from every screen" do
    visit root_path

    click_on "Your splits"

    assert_selector "h1", text: "Your splits"
  end

  test "once everyone has paid history says so instead of a figure" do
    split = save_split_called "Dinner at Rosalia", amount: "100", people_count: 2
    split.participants.each { |participant| participant.update!(paid_at: Time.current) }

    visit splits_path

    assert_text "All paid"
  end

  private

  def save_split_called(title, amount:, people_count:)
    visit root_path
    fill_in "Amount", with: amount
    fill_in "People", with: people_count
    click_on "Save and add names"
    assert_selector "h1", text: "Edit split"

    fill_in "Title", with: title
    click_on "Save"
    assert_text "Saved."

    Split.find(current_url[%r{/splits/(\d+)}, 1])
  end
end
