require "test_helper"

# The stepper buttons are a "+" and a "−", so their accessible name comes from
# aria-label rather than their text. Capybara ignores aria-label unless told
# otherwise, which would leave icon-only buttons unreachable in tests — and
# untested accessible names are the ones that rot.
Capybara.enable_aria_label = true

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # 375 x 812 is the viewport the spec designs for, so the tests drive the app
  # at the size most people will actually use it at rather than at a desktop
  # width where a cramped mobile layout would still pass.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 375, 812 ]
end
