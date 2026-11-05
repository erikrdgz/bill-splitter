require "test_helper"

# A guard rather than a behaviour test: double-tap zoom only happens on a real
# iPhone, which system tests cannot drive. If this rule is lost, typing the
# same digit twice on the keypad zooms the page instead of entering it.
class TapZoomTest < ActiveSupport::TestCase
  test "controls opt out of double-tap zoom" do
    stylesheet = Rails.root.join("app/assets/tailwind/application.css").read

    assert_match(/button, a, summary, label, input, select, textarea, \.keypad-panel \{ touch-action: manipulation; \}/, stylesheet)
  end
end
