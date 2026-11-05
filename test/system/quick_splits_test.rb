require "application_system_test_case"

# The quick split's whole promise is that the numbers move as you type, with no
# request in between. That cannot be proved by a controller test, because there
# is no second request to assert on — so these drive a real browser.
class QuickSplitsTest < ApplicationSystemTestCase
  test "no amount yet means no figures" do
    visit root_path

    assert_equal [], share_amounts
    assert_text "0 people"
    assert_button "Save split", disabled: true
    assert_no_text "one cent more"
  end

  test "shares appear as the amount is typed, with no save in between" do
    visit root_path

    enter_bill_amount("100")
    set_people_count(2)

    assert_equal [ "$50", "$50" ], share_amounts
  end

  # The spec's headline example.
  test "a hundred dollars between three people is 33.34, 33.33, 33.33" do
    visit root_path

    enter_bill_amount("100")
    set_people_count("3")

    assert_equal [ "$33.34", "$33.33", "$33.33" ], share_amounts
    assert_text "Includes a 1¢ rounding adjustment."
  end

  test "the shares always add up to the amount, cents and all" do
    visit root_path

    enter_bill_amount("100.01")
    set_people_count("3")

    assert_equal [ "$33.34", "$33.34", "$33.33" ], share_amounts
    assert_text "Includes a 1¢ rounding adjustment."
  end

  test "an amount that divides cleanly says nothing about cents" do
    visit root_path

    enter_bill_amount("90")
    set_people_count("3")

    assert_equal [ "$30", "$30", "$30" ], share_amounts
    assert_no_text "one cent more"
  end

  test "the stepper adds and removes rows" do
    visit root_path
    enter_bill_amount("60")
    set_people_count(2)

    click_on "Add", exact: true

    assert_equal [ "$20", "$20", "$20" ], share_amounts

    all("[data-quick-split-logic-target=shares] > li").last.send_keys(:delete)

    assert_equal [ "$30", "$30" ], share_amounts
  end

  test "the last draft person can be removed" do
    visit root_path

    click_on "Add", exact: true
    all("[data-quick-split-logic-target=shares] > li").last.send_keys(:delete)
    assert_equal 0, share_amounts.size
  end

  test "the stepper stops at twenty people" do
    visit root_path
    enter_bill_amount("100")

    set_people_count("19")
    click_on "Add", exact: true

    assert_equal 20, share_amounts.size
    assert_button "Add", exact: true, disabled: true
  end

  test "the people counter is read only" do
    visit root_path
    assert_text "0 people"
    assert_no_selector "input[type=number]"
    assert_no_button "One more person"
    assert_no_button "One fewer person"
    click_on "Add", exact: true
    assert_text "1 person"
  end

  test "letters typed into the amount are ignored rather than breaking the math" do
    visit root_path
    enter_bill_amount("1oo")
    set_people_count(2)

    assert_equal [ "$0.50", "$0.50" ], share_amounts
  end

  test "Add previews a thousand dollar bill for six people without saving" do
    visit root_path
    enter_bill_amount("1000")
    6.times { click_on "Add", exact: true }
    assert_text "6 people"
    assert_equal [ "$166.67", "$166.67", "$166.67", "$166.67", "$166.66", "$166.66" ], share_amounts
    assert_current_path root_path
    assert_selector "[data-share-row-slider]", count: 6
    assert_no_text "Start even."
  end

  test "draft percentages leave the organizer remainder and survive connection" do
    visit root_path
    enter_bill_amount("1000")
    set_people_count(2)
    fill_in "Person 1's percentage", with: "20"
    find_field("Person 1's percentage").send_keys(:tab)
    fill_in "Person 2's percentage", with: "20"
    find_field("Person 2's percentage").send_keys(:tab)
    assert_equal [ "$200", "$200" ], share_amounts
    assert_text "You pay\n$600"
    click_on "Connect Person 1"
    fill_in "Name", with: "Alex"
    find("[role=option]", text: "Create contact “Alex”").click
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true
    assert_current_path root_path
    assert_equal [ "$200", "$200" ], share_amounts
    click_on "Review requests"
    assert_text "Paying in cash"
    assert_text "$200.00"
    click_on "Edit split", exact: true
    assert_row_amounts [ "$200.00", "$200.00" ]
    assert_text "You pay"
    assert_text "$600.00"
  end

  test "swiping a draft card reveals delete without moving its slider" do
    visit root_path
    enter_bill_amount("90")
    set_people_count(2)
    click_on "Add", exact: true
    assert_selector "[data-quick-split-logic-target=shares] > li", count: 3
    card = all("[data-quick-split-logic-target=shares] > li").last
    # Pointer events exercise the same horizontal threshold as touch/mouse,
    # while a separate browser pass verifies the real gesture visually.
    page.execute_script(<<~JS, card)
      const card = arguments[0]
      card.setPointerCapture = () => {}
      card.dispatchEvent(new PointerEvent("pointerdown", {bubbles:true, clientX:280, clientY:50, pointerId:1}))
      card.dispatchEvent(new PointerEvent("pointermove", {bubbles:true, clientX:180, clientY:52, pointerId:1}))
      card.dispatchEvent(new PointerEvent("pointerup", {bubbles:true, clientX:180, clientY:52, pointerId:1}))
    JS
    within card do
      assert_button "Remove Person 3"
      click_on "Remove Person 3"
    end
    assert_text "2 people"
    assert_equal [ "$45", "$45" ], share_amounts
    assert_current_path root_path
  end

  private

  # Only the live rows, never the <template> beside them: a real browser keeps
  # template content out of the document, so this selector cannot see it.
  def share_amounts
    count = find("[data-quick-split-logic-target=peopleCount]", visible: :all).value.to_i
    assert_selector "ol[data-quick-split-logic-target=shares] > li", count: count
    all("ol[data-quick-split-logic-target='shares'] > li [data-share-row-amount]").map(&:text)
  end
end
