require "application_system_test_case"

class MobileInteractionsTest < ApplicationSystemTestCase
  test "Connect searches saved contacts and offers explicit creation inline" do
    visit root_path
    enter_bill_amount("100")
    set_people_count(2)
    click_on "Save split"
    click_on "Name Person 1"
    fill_in "Find a name", with: "Maya Chen"
    click_on "Add “Maya Chen” as a new person"
    assert_link "Name Maya Chen"
    click_on "New split"
    click_on "Add", exact: true
    click_on "Connect Person 1"
    within "dialog[open]" do
      assert_no_selector "[role=option]"
      assert_no_text "Maya Chen"
      assert_equal "connection-title", page.evaluate_script("document.activeElement.id")
      fill_in "Name", with: "ma"
      assert_selector "[role=option]", text: "Maya Chen"
      fill_in "Name", with: "Maya Chen"
      assert_selector "[role=option]", text: "Maya Chen", count: 1
      assert_no_selector "[role=option]", text: "Create contact"
      find("[role=option]", text: "Maya Chen").click
      choose "Cash", allow_label_click: true
      click_on "Connect", exact: true
    end
    assert_button "Connect Maya Chen"
    click_on "Add", exact: true
    click_on "Connect Person 2"
    within "dialog[open]" do
      fill_in "Name", with: "Nina Patel"
      assert_selector "[role=option]", text: "Create contact “Nina Patel”"
      find_field("Name").send_keys(:arrow_down, :enter)
      assert_no_selector "[role=option]"
      choose "Cash", allow_label_click: true
      click_on "Connect", exact: true
    end
    assert_button "Connect Nina Patel"
    assert_current_path root_path
  end

  test "quarter swipe reveals an icon and a full swipe deletes" do
    visit root_path
    enter_bill_amount("90")
    set_people_count(3)
    card = all("[data-quick-split-logic-target=shares] > li").last
    swipe(card, 0.25)
    within card do
      assert_selector "button.swipe-delete svg"
      assert_button "Remove Person 3"
    end
    assert_text "3 people"
    click_on "Remove Person 3"
    assert_text "2 people"
    card = all("[data-quick-split-logic-target=shares] > li").last
    swipe(card, 0.95)
    assert_text "1 person"
    assert_no_button "Connect Person 2"
  end

  test "delete surface grows with the drag then springs back without deleting below threshold" do
    visit root_path
    set_people_count(2)
    card = all("[data-quick-split-logic-target=shares] > li").last
    execute_script(<<~JS, card)
      const card = arguments[0]
      card.setPointerCapture = () => {}
      card.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, clientX: 320, clientY: 50, pointerId: 1}))
      card.dispatchEvent(new PointerEvent('pointermove', {bubbles: true, clientX: 320 - card.clientWidth * .35, clientY: 50, pointerId: 1}))
    JS
    small_width = card.find(".swipe-delete").native.rect.width
    execute_script(<<~JS, card)
      const card = arguments[0]
      card.dispatchEvent(new PointerEvent('pointermove', {bubbles: true, clientX: 320 - card.clientWidth * .65, clientY: 50, pointerId: 1}))
    JS
    large_width = card.find(".swipe-delete").native.rect.width
    assert_operator large_width, :>, small_width + 50
    execute_script("arguments[0].dispatchEvent(new PointerEvent('pointerup', {bubbles: true, pointerId: 1}))", card)
    assert_eventually { (card.find(".swipe-delete").native.rect.width - 56).abs < 1 }
    assert_text "2 people"
    within card do
      assert_button "Remove Person 2"
      click_on "Remove Person 2"
    end
    assert_text "1 person"
  end

  # A card held open is a question waiting for an answer. Left alone it answers
  # itself rather than sitting there looking like a pending action.
  test "a revealed card springs back on its own if nobody answers it" do
    visit root_path
    set_people_count(2)
    card = all("[data-quick-split-logic-target=shares] > li").last
    shorten_auto_close(card)

    swipe(card, 0.25)

    assert_selector "[data-swipe-open=true]"
    within(card) { assert_button "Remove Person 2" }

    assert_eventually("the card never sprang back") { card["data-swipe-open"] == "false" }
    within(card) { assert_no_button "Remove Person 2" }
    # It closed; it did not delete.
    assert_text "2 people"
  end

  # ArrowLeft reveals the card and focuses the delete button. The timer still
  # closes it — nothing but a full swipe or a tap keeps it open — but closing
  # hides the focused button, so focus is handed back to the card rather than
  # dropped on the body.
  test "a card revealed by the keyboard also springs back, without stranding focus" do
    visit root_path
    set_people_count(2)
    card = all("[data-quick-split-logic-target=shares] > li").last
    shorten_auto_close(card)

    card.send_keys(:arrow_left)

    assert_selector "[data-swipe-open=true]"
    assert_equal "Remove Person 2", page.evaluate_script("document.activeElement.getAttribute('aria-label')")

    assert_eventually("the card never sprang back") { card["data-swipe-open"] == "false" }

    assert_equal "LI", page.evaluate_script("document.activeElement.tagName")
    assert_text "2 people"
  end

  test "the timer never interrupts a delete that was actually tapped" do
    visit root_path
    set_people_count(2)
    card = all("[data-quick-split-logic-target=shares] > li").last
    shorten_auto_close(card)

    swipe(card, 0.25)
    within(card) { click_on "Remove Person 2" }

    assert_text "1 person"
  end

  test "a full swipe collapses the middle card without hiding the next person" do
    visit root_path
    enter_bill_amount("90")
    set_people_count(3)
    fill_in "Person 1's percentage", with: "20"
    find_field("Person 1's percentage").send_keys(:tab)
    cards = all("[data-quick-split-logic-target=shares] > li")
    last_card = cards.last
    swipe(cards[1], 0.95)
    assert_selector ".is-deleting"
    assert_text "2 people"
    assert_selector "[data-quick-split-logic-target=shares] > li", count: 2
    assert_equal last_card, all("[data-quick-split-logic-target=shares] > li").last
    assert_button "Edit Person 1's amount", text: "$18"
    assert_button "Edit Person 2's amount", text: "$30"
    assert_no_selector ".is-deleting"
  end

  test "a refused saved swipe restores the card after its exit" do
    visit root_path
    enter_bill_amount("100")
    set_people_count(2)
    click_on "Save split"
    click_on "Custom"
    check "Lock Person 1"
    check "Lock Person 2"
    click_on "Save amounts"
    assert_text "Saved."
    card = all("#participants > li").last
    swipe(card, 0.95)
    assert_text "Unlock a row first"
    assert_selector "#participants > li", count: 2
    assert_no_selector ".is-deleting"
    # Explicitly, because the exit animation holds the row at zero opacity and a
    # restore that forgets to undo that leaves a row that is present but
    # invisible — which otherwise only shows up as a flaky text assertion.
    assert_eventually("the restored card stayed invisible") do
      page.evaluate_script(
        "getComputedStyle(document.querySelector('#participants > li:nth-of-type(2)')).opacity"
      ).to_f > 0.95
    end
    assert_row_amounts [ "$50.00", "$50.00" ]
  end

  test "tapping outside either amount editor cancels the draft" do
    visit root_path
    enter_bill_amount("100")
    set_people_count(2)
    find_field("Amount").click
    within "dialog[open]" do
      click_on "Clear", exact: true
      click_on "9", exact: true
    end
    assert_field "Amount", with: "9"
    tap_backdrop(x: 180, y: 80)
    assert_no_selector "dialog[open]"
    assert_field "Amount", with: "100"
    assert_button "Edit Person 1's amount", text: "$50"

    click_on "Edit Person 1's amount"
    within "dialog[open]" do
      click_on "Clear", exact: true
      click_on "2", exact: true
    end
    tap_backdrop
    assert_no_selector "dialog[open]"
    assert_button "Edit Person 1's amount", text: "$50"
    assert_field "Amount", with: "100"
  end

  test "tapping outside Connect returns to the unchanged split" do
    visit root_path
    set_people_count(1)
    click_on "Connect Person 1"
    fill_in "Name", with: "Unfinished name"
    tap_backdrop
    assert_no_selector "dialog[open]"
    assert_button "Connect Person 1"
    assert_no_button "Connect Unfinished name"
    click_on "Connect Person 1"
    assert_field "Name", with: ""
    # Inner taps keep the drawer open.
    find_field("Name").click
    assert_selector "dialog[open]"
  end

  test "backdrop dismissal works immediately and after reopening" do
    visit root_path
    set_people_count(1)
    2.times do
      click_on "Connect Person 1"
      tap_backdrop(x: 180, y: 3)
      assert_no_selector "dialog[open]"
      assert_button "Connect Person 1"
    end
    find_field("Amount").click
    tap_backdrop(x: 180, y: 80)
    assert_no_selector "dialog[open]"
  end

  test "default amount is centered and focus returns without a box" do
    visit root_path
    styles = page.evaluate_script(<<~JS)
      (() => {
        const input = document.querySelector('.amount-input')
        const symbol = document.querySelector('.bill-amount > span')
        const left = symbol.getBoundingClientRect().left
        const right = input.getBoundingClientRect().right
        return {input: getComputedStyle(input, '::placeholder').color,
          symbol: getComputedStyle(symbol).color, center: (left + right) / 2, viewport: innerWidth}
      })()
    JS
    assert_equal styles["symbol"], styles["input"]
    assert_in_delta styles["viewport"] / 2, styles["center"], 2
    enter_bill_amount("1000")
    assert_no_selector "dialog[open]"
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.bill-amount')).boxShadow")
  end

  private

  def tap_backdrop(x: 3, y: 3)
    page.driver.browser.action.move_to_location(x, y).click.perform
  end

  # The real wait is five seconds, which is right for a thumb and wrong for a
  # test suite. Shortening the Stimulus value exercises the same code path.
  def shorten_auto_close(card, milliseconds = 200)
    execute_script(
      "arguments[0].setAttribute('data-swipe-logic-reveal-timeout-value', arguments[1])",
      card, milliseconds
    )
  end

  def swipe(card, fraction)
    execute_script(<<~JS, card, fraction)
      const [card, fraction] = arguments
      card.setPointerCapture = () => {}
      // A real pointerdown focuses the card: it has tabindex="0". Synthetic
      // events do not, and a helper that skips this hides focus-dependent bugs.
      card.focus()
      const start = card.clientWidth - 4
      card.dispatchEvent(new PointerEvent('pointerdown', {bubbles: true, clientX: start, clientY: 50, pointerId: 1}))
      card.dispatchEvent(new PointerEvent('pointermove', {bubbles: true, clientX: start - card.clientWidth * fraction, clientY: 52, pointerId: 1}))
      card.dispatchEvent(new PointerEvent('pointerup', {bubbles: true, clientX: start - card.clientWidth * fraction, clientY: 52, pointerId: 1}))
    JS
  end
end
