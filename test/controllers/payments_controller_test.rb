require "test_helper"

class PaymentsControllerTest < ActionDispatch::IntegrationTest
  # The spec's test.
  test "I paid sets paid_at on that participant only" do
    split = splits(:dinner)
    marissa = participants(:dinner_marissa)

    freeze_time do
      post share_payment_url(split.share_token, marissa), as: :turbo_stream

      assert_response :success
      assert_equal Time.current, marissa.reload.paid_at
    end

    assert_nil participants(:dinner_marcus).reload.paid_at
    assert_nil participants(:dinner_placeholder).reload.paid_at
  end

  test "paying answers with a Turbo Stream that replaces just that row" do
    marissa = participants(:dinner_marissa)

    post share_payment_url(splits(:dinner).share_token, marissa), as: :turbo_stream

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match ActionView::RecordIdentifier.dom_id(marissa), response.body
    assert_match "owed", response.body
  end

  test "paying leaves the amounts alone" do
    split = splits(:dinner)

    post share_payment_url(split.share_token, participants(:dinner_marissa)), as: :turbo_stream

    assert_equal [ 3334, 3333, 3333 ], split.reload.participants.map(&:amount_cents)
    assert_equal 6666, split.owed_cents
  end

  # Two friends tapping the same row in a group chat is normal, not a conflict.
  test "paying twice is not an error and does not move the time it was paid" do
    marissa = participants(:dinner_marissa)
    token = splits(:dinner).share_token

    post share_payment_url(token, marissa), as: :turbo_stream
    paid_at = marissa.reload.paid_at

    travel 1.hour do
      post share_payment_url(token, marissa), as: :turbo_stream
    end

    assert_response :success
    assert_equal paid_at, marissa.reload.paid_at
  end

  test "a wrong token cannot mark anybody paid" do
    post share_payment_url("not-a-real-token", participants(:dinner_marissa)), as: :turbo_stream

    assert_response :not_found
    assert_nil participants(:dinner_marissa).reload.paid_at
  end

  # The token is scoped to its own split, so it cannot reach into another one.
  test "a token cannot mark a participant of a different split paid" do
    post share_payment_url(splits(:dinner).share_token, participants(:stranger_one)),
         as: :turbo_stream

    assert_response :not_found
    assert_nil participants(:stranger_one).reload.paid_at
  end
end
