require "test_helper"

# The stepper buttons are a "+" and a "−", so their accessible name comes from
# aria-label rather than their text. Capybara ignores aria-label unless told
# otherwise, which would leave icon-only buttons unreachable in tests — and
# untested accessible names are the ones that rot.
Capybara.enable_aria_label = true

# Once the system suite passed fifty tests, Minitest began running it in
# parallel — one browser per processor, which is fourteen headless Chromes on
# this machine. Everything still works; it just takes longer to answer, and
# Capybara's two-second default started timing out on perfectly good pages.
#
# This is a maximum, not a pause: a test that passes immediately still passes
# immediately. It only buys patience for the ones competing for a core.
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # 375 x 812 is the viewport the spec designs for, so the tests drive the app
  # at the size most people will actually use it at rather than at a desktop
  # width where a cramped mobile layout would still pass.
  #
  # Reduced motion makes view transitions instant. While one is running the page
  # ignores clicks, so a test that clicks the next button the moment it appears
  # could lose that click to an animation it does not care about.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 375, 812 ] do |options|
    options.add_argument("--force-prefers-reduced-motion")
  end

  private

  # For the tests that are about an animation: undo the suite's reduced motion
  # for this one browser before the page loads.
  def with_motion
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
                                    features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
  end

  # Saving is the last of three steps: bill, people, review. The people step
  # refuses to go on until every row is connected, so a test that only cares
  # about the money connects everyone with cash first.
  def save_split_and_open_editor
    save_split
    click_on "Edit split"
    assert_selector "h1", text: "Edit split"
  end

  def save_split
    connect_everyone_with_cash
    click_on "Next"
    click_on "Save split"
    assert_selector "h1", text: "Send requests"
  end

  # Cash needs no handle, so it is the quickest way to make a row real. Rows
  # that are already connected are skipped, which lets a test connect the
  # one or two people it cares about and leave the rest to this.
  def connect_everyone_with_cash
    start_group
    count = find("input[data-quick-split-logic-target=peopleCount]", visible: :all).value.to_i
    (1..count).each do |position|
      next unless has_button?("Connect Person #{position}", wait: 0)

      connect_person("Person #{position}", "Guest #{position}")
    end
  end

  # Creates a brand-new contact from the search box and connects the row to it.
  # Anything but cash needs a phone number to text the pay link to.
  def connect_person(row_label, name, method: "cash", phone: nil)
    # The group view fades in just after "Split up", and a click that lands
    # mid-fade can be swallowed, so ask again if the sheet did not open.
    2.times do
      click_on "Connect #{row_label}"
      break if has_selector?("dialog[open]", wait: 2)
    end
    fill_in "Name", with: name
    # An earlier split in the same test may already have saved this name, in
    # which case the search offers the contact itself instead of "Create".
    find("[role=option]", text: /#{Regexp.escape(name)}”?\z/).click
    choose Participant::PAYMENT_METHODS.fetch(method), allow_label_click: true
    fill_in "Phone number", with: phone if phone
    click_on "Connect", exact: true
    assert_button "Connect #{name}"
  end

  # Fills in the bill, sets the head count, saves, and reopens the saved split
  # in the composer. The editor and the new-split screen are the same form, so
  # this is the quickest way to a split that is already in the database.
  def open_editor_for(amount, people_count)
    visit root_path
    enter_bill_amount(amount)
    set_people_count(people_count)
    save_split_and_open_editor
  end

  # Opens the bill header in the composer, changes what was asked for, and
  # closes it again. Works the same on a new split and a saved one.
  def edit_bill_details(title: nil, amount: nil)
    click_on "Edit bill details"
    fill_in "What's this for?", with: title if title
    # enter_bill_amount closes the header itself once it has set the amount.
    amount ? enter_bill_amount(amount) : click_on("Done editing bill")
  end

  # Only the live rows, never the <template> beside them: a real browser keeps
  # template content out of the document, so this selector cannot see it.
  def share_amounts
    count = find("[data-quick-split-logic-target=peopleCount]", visible: :all).value.to_i
    assert_selector "ol[data-quick-split-logic-target=shares] > li", count: count
    all("ol[data-quick-split-logic-target='shares'] > li [data-share-row-amount]").map(&:text)
  end

  def enter_bill_amount(amount, label: "Amount")
    find_field(label)
    group = has_selector?(".composer[data-stage=group]", wait: 0)
    inline = has_selector?(".composer[data-stage=details]", wait: 0)
    click_on "Edit bill details" if group && has_button?("Edit bill details", wait: 0)
    find_field(label).click
    within(inline ? ".entry-keypad" : "dialog[open][aria-label='Enter bill amount']") do
      click_on "Clear", exact: true
      amount.to_s.each_char do |digit|
        next unless digit.match?(/[0-9.]/)
        click_on(digit == "." ? "Decimal point" : digit, exact: true)
      end
      click_on "Set amount" unless inline
      click_on "Accept amount" if inline && has_button?("Accept amount", wait: 0)
    end
    click_on "Done editing bill" if group
  end

  def start_group
    return if has_selector?(".composer[data-stage=group]", wait: 0)

    enter_bill_amount("100") if find_field("Amount").value.to_f <= 0
    fill_in "What's this for?", with: "Dinner" if find_field("What's this for?").value.blank?
    click_on "Split up"
    assert_selector ".composer[data-stage=group]"
  end

  def set_people_count(count)
    start_group
    count = count.to_i
    current = find("input[data-quick-split-logic-target=peopleCount]", visible: :all).value.to_i
    (count - current).times { click_on "Add person", exact: true } if count > current
    (current - count).times do
      all("[data-quick-split-logic-target=shares] > li").last.send_keys(:delete)
    end if count < current
    assert_selector "[data-quick-split-logic-target=shares] > li", count: count
  end

  # Why not `all(...).map(&:text)`: `all` returns the elements that are on the
  # page at that instant and never retries. Half of this app's screens change
  # under a Turbo Stream or a redirect, so a plain read either catches the old
  # page or blows up with a stale element reference once it swaps mid-read.
  #
  # assert_selector retries until it matches or times out, which is what makes
  # these assertions deterministic.
  def assert_row_amounts(expected)
    assert_selector "ol#participants > li", count: expected.size

    expected.each_with_index do |amount, index|
      assert_selector row_selector(index, "amount"), text: amount
    end
  end

  def assert_row_percentages(expected)
    expected.each_with_index do |percentage, index|
      assert_selector row_selector(index, "percentage"), text: percentage
    end
  end

  # data-row-amount rather than the Stimulus target, so the same assertion works
  # on the editor, the share page and the organizer's detail page.
  def row_selector(index, target)
    hook = target == "amount" ? "[data-row-amount]" : "[data-split-logic-target='#{target}']"

    "ol#participants > li:nth-of-type(#{index + 1}) #{hook}"
  end

  # Capybara's matchers retry; reading a value out of JavaScript does not. This
  # waits the same way for something that settles a moment later — like the
  # scroll position Turbo restores after morphing a page.
  def assert_eventually(message = nil, timeout: Capybara.default_max_wait_time)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

    loop do
      return if yield
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end

    flunk(message || "the condition was never true within #{timeout} seconds")
  end
end
