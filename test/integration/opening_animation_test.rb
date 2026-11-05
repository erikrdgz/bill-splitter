require "test_helper"

# The opening animation plays on a visitor's first full page load and again after
# half an hour away. The server decides, so the overlay is either in the HTML or
# it is not; there is no flash-then-hide.
class OpeningAnimationTest < ActionDispatch::IntegrationTest
  setup do
    @original = Rails.configuration.x.intro
    Rails.configuration.x.intro = true
  end

  teardown { Rails.configuration.x.intro = @original }

  test "the first page load plays the intro and later pages do not" do
    get root_url
    assert_select ".intro[data-turbo-temporary]", 1

    get splits_url
    assert_select ".intro", 0

    get root_url
    assert_select ".intro", 0
  end

  test "coming back after half an hour away plays it again" do
    get root_url
    assert_select ".intro", 1

    travel 31.minutes do
      get root_url
      assert_select ".intro", 1
    end
  end

  test "regular use keeps the clock fresh, so it does not replay mid-session" do
    get root_url
    travel 20.minutes do
      get splits_url
    end
    travel 40.minutes do
      get root_url
      assert_select ".intro", 0
    end
  end

  test "a Turbo visit or prefetch never plays it" do
    get root_url, headers: { "X-Turbo-Request-Id" => "abc" }
    assert_select ".intro", 0

    get root_url, headers: { "X-Sec-Purpose" => "prefetch" }
    assert_select ".intro", 0
  end

  test "the intro can be switched off" do
    Rails.configuration.x.intro = false

    get root_url
    assert_select ".intro", 0
  end

  test "the nav logo is the cut wordmark, named for the app, without a period" do
    Rails.configuration.x.intro = false # the intro draws a second copy of the logo
    get root_url

    assert_select "a.wordmark[aria-label='Bill Splitter']" do
      assert_select ".wordmark-art", text: "$plit"
    end
    assert_select ".wordmark-art", text: /plit\./, count: 0
  end
end
