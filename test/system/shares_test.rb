require "application_system_test_case"

class SharesTest < ApplicationSystemTestCase
  # A friend opening the link has no cookie, no account, and never gets one.
  test "a friend opens the link and sees what everyone owes" do
    visit share_path(splits(:dinner).share_token)

    assert_selector "h1", text: "Dinner at Rosalia"
    assert_row_amounts [ "$33.34", "$33.33", "$33.33" ]
    assert_text "Still owed\n$100.00"
  end

  test "tapping I paid confirms the name first, then marks the row" do
    visit share_path(splits(:dinner).share_token)

    within "##{dom_id(participants(:dinner_marissa))}" do
      accept_confirm(/Mark Marissa as paid/) { click_on "I paid" }
    end

    # The row is replaced in place by a Turbo Stream — no page reload.
    assert_selector "##{dom_id(participants(:dinner_marissa))}", text: /Paid/
    assert_text "Still owed\n$66.66"
  end

  test "changing your mind at the confirmation marks nothing" do
    visit share_path(splits(:dinner).share_token)

    within "##{dom_id(participants(:dinner_marissa))}" do
      dismiss_confirm { click_on "I paid" }
    end

    assert_text "Still owed\n$100.00"
    assert_no_text "Paid"
  end

  test "only the row that was tapped is marked" do
    visit share_path(splits(:dinner).share_token)

    within "##{dom_id(participants(:dinner_marissa))}" do
      accept_confirm { click_on "I paid" }
    end

    assert_selector "##{dom_id(participants(:dinner_marissa))}", text: /Paid/
    assert_selector "##{dom_id(participants(:dinner_marcus))} button", text: "I paid"
  end

  test "when everybody has paid the page says so" do
    splits(:dinner).participants.each { |participant| participant.update!(paid_at: Time.current) }

    visit share_path(splits(:dinner).share_token)

    assert_text "Everyone has paid."
    assert_no_button "I paid"
  end

  test "a wrong link is a not-found page, not somebody else's bill" do
    visit share_path("not-a-real-token")

    assert_no_text "Dinner at Rosalia"
  end

  # The organizer's side.

  test "the organizer sees who has paid and can copy the link" do
    split = open_editor_and_share

    assert_selector "h2", text: "Who has paid"
    assert_field "Share link", with: share_url(split.share_token)

    click_on "Copy"

    # Either the clipboard worked or the page said how to copy by hand. It never
    # claims a copy that did not happen.
    assert_selector "[role=status]", text: /copied|⌘C/i
  end

  test "the organizer's page does not offer to pay for people" do
    open_editor_and_share

    assert_no_button "I paid"
    assert_text "Unpaid"
  end

  private

  def open_editor_and_share
    visit root_path
    fill_in "Amount", with: "100"
    fill_in "People", with: "3"
    click_on "Save and add names"
    assert_selector "h1", text: "Edit split"

    click_on "Share and request money"
    assert_selector "h2", text: "Share this split"

    Split.find(current_url[%r{/splits/(\d+)}, 1])
  end

  def dom_id(record)
    ActionView::RecordIdentifier.dom_id(record)
  end
end
