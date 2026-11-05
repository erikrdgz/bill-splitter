require "test_helper"

# The opening animation plays once per browser session. The server decides, so
# the overlay is either in the HTML or it is not; there is no flash-then-hide.
class OpeningAnimationTest < ActionDispatch::IntegrationTest
  setup do
    @original = Rails.configuration.x.intro
    Rails.configuration.x.intro = true
  end

  teardown { Rails.configuration.x.intro = @original }

  test "the first page of a session plays the intro and later pages do not" do
    get root_url
    assert_select ".intro[data-turbo-temporary]", 1

    get splits_url
    assert_select ".intro", 0

    get root_url
    assert_select ".intro", 0
  end

  test "the intro can be switched off" do
    Rails.configuration.x.intro = false

    get root_url
    assert_select ".intro", 0
  end

  test "the nav logo is the split wordmark, named for the app, without a period" do
    Rails.configuration.x.intro = false # the intro draws a second copy of the logo
    get root_url

    assert_select "a.wordmark[aria-label='Bill Splitter']" do
      assert_select ".wordmark-half", 2
    end
    assert_select ".wordmark-half", text: "$plit", count: 2
    assert_select ".wordmark-half", text: /plit\./, count: 0
  end
end
