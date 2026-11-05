require "application_system_test_case"

class AmountKeypadsTest < ApplicationSystemTestCase
  test "total typing updates the existing amount with a clear backdrop and cancel restores it" do
    visit root_path
    enter_bill_amount("1000")
    set_people_count(2)
    find_field("Amount").click
    within "dialog[open]" do
      click_on "Clear", exact: true
      type_amount "250"
      assert_selector ".keypad-display", text: "$250"
      assert_equal "inset(50%)", page.evaluate_script("getComputedStyle(document.querySelector('dialog[open] .keypad-display')).clipPath")
    end
    assert_equal "250", find_field("Amount", visible: :all).value
    assert_equal "rgba(0, 0, 0, 0)", page.evaluate_script("getComputedStyle(document.querySelector('dialog[open]'), '::backdrop').backgroundColor")
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('dialog[open]'), '::backdrop').backdropFilter")
    assert_equal [ "$125", "$125" ], all("[data-share-row-amount]", visible: :all).map(&:text)
    click_on "Cancel amount"
    assert_field "Amount", with: "1000"
    assert_selector "[data-share-row-amount]", text: "$500", count: 2
  end

  test "a named person's keypad keeps context and saves exact cents without changing the bill" do
    visit root_path
    enter_bill_amount("1000")
    set_people_count(2)
    click_on "Connect Person 1"
    fill_in "Name", with: "Alex"
    find("[role=option]", text: "Create contact “Alex”").click
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true
    click_on "Edit Alex's amount"
    within "dialog[open][aria-label='Amount for Alex']" do
      assert_selector ".keypad-panel .keypad-context", text: "Alex"
      assert_selector ".sheet-content > .keypad-display", text: "$500"
      click_on "Clear", exact: true
      type_amount "200.25"
      click_on "Set amount"
    end
    assert_button "Edit Alex's amount", text: "$200.25"
    assert_button "Edit Person 2's amount", text: "$500"
    assert_field "Amount", with: "1000"
    assert_text "You pay\n$299.75"
    click_on "Edit Alex's amount"
    within "dialog[open]" do
      click_on "Clear", exact: true
      type_amount "999"
      click_on "Set amount"
      assert_text "Available: $500."
      click_on "Cancel amount"
    end
    assert_button "Edit Alex's amount", text: "$200.25"
    click_on "Save split"
    assert_row_amounts [ "$200.25", "$500.00" ]
    click_on "Edit Alex's amount"
    within "dialog[open][aria-label='Amount for Alex']" do
      click_on "Clear", exact: true
      type_amount "20.12"
      click_on "Set amount"
    end
    click_on "Save amounts"
    assert_row_amounts [ "$20.12", "$500.00" ]
  end

  test "slider gestures and arrows use whole dollars while untouched exact shares stay put" do
    visit root_path
    enter_bill_amount("100")
    set_people_count(3)
    slider = find_field("Person 1's share")
    execute_script(<<~JS, slider)
      arguments[0].value = 2237
      arguments[0].dispatchEvent(new Event('input', {bubbles: true}))
    JS
    assert_button "Edit Person 1's amount", text: "$22"
    assert_button "Edit Person 2's amount", text: "$33.33"
    slider.send_keys(:arrow_right)
    assert_button "Edit Person 1's amount", text: "$23"
    slider.send_keys(:end)
    assert_button "Edit Person 1's amount", text: "$33", exact_text: true
    assert_text "You pay\n$0.34"
    click_on "Edit Person 1's amount"
    within "dialog[open]" do
      click_on "Clear", exact: true
      type_amount "33.34"
      click_on "Set amount"
    end
    assert_text "You pay\n$0"
  end

  private

  def type_amount(value)
    value.each_char { |digit| click_on(digit == "." ? "Decimal point" : digit, exact: true) }
  end
end
