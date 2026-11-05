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
  driven_by :selenium, using: :headless_chrome, screen_size: [ 375, 812 ]

  private

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
