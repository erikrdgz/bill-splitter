require "test_helper"

class PaymentProfilesControllerTest < ActionDispatch::IntegrationTest
  test "a browser with no profile yet is offered the form, not an error" do
    get edit_payment_profile_url

    assert_response :success
    assert_select "turbo-frame#payment_profile"
    assert_select "input[name=?]", "payment_profile[venmo_handle]"
  end

  test "saving handles refreshes the page, because the request buttons depend on them" do
    patch payment_profile_url, params: { payment_profile: {
      venmo_handle: "@erik-r", cashapp_cashtag: "$erikr"
    } }, as: :turbo_stream

    assert_response :success
    assert_select "turbo-stream[action=refresh]"

    profile = PaymentProfile.last

    assert_equal "erik-r", profile.venmo_handle
    assert_equal "erikr", profile.cashapp_cashtag
  end

  test "a bad handle is refused and the form stays open" do
    patch payment_profile_url, params: { payment_profile: { venmo_handle: "not a username" } },
                               as: :turbo_stream

    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /is not a Venmo username/
  end

  test "show restores the frame, which is what Cancel goes back to" do
    get payment_profile_url

    assert_response :success
    assert_select "turbo-frame#payment_profile"
  end

  # Profiles are per browser, like everything else here.
  test "one browser cannot read or write another's handles" do
    patch payment_profile_url, params: { payment_profile: { venmo_handle: "mine" } },
                               as: :turbo_stream

    assert_not_equal "mine", payment_profiles(:organizer).reload.venmo_handle
    assert_equal 1, PaymentProfile.where(venmo_handle: "mine").count
  end
end
