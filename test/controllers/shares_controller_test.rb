require "test_helper"

class SharesControllerTest < ActionDispatch::IntegrationTest
  # The spec's test.
  test "the share page loads by token" do
    get share_url(splits(:dinner).share_token)

    assert_response :success
    assert_select "h1", "Dinner at Rosalia"
  end

  test "a wrong token returns 404" do
    get share_url("not-a-real-token")

    assert_response :not_found
  end

  # No account, no cookie, no owner check: the token is the credential.
  test "the share page works for a browser that owns nothing" do
    get share_url(splits(:stranger_brunch).share_token)

    assert_response :success
    assert_select "h1", "Someone else's brunch"
  end

  test "the share page shows everyone and what they owe" do
    get share_url(splits(:dinner).share_token)

    assert_select "ol#participants > li", 3
    assert_select "ol#participants > li", text: /Marissa.*\$33\.34/m
    assert_select "ol#participants > li", text: /Person 3.*\$33\.33/m
  end

  test "the share page offers I paid on every unpaid row" do
    get share_url(splits(:dinner).share_token)

    assert_select "summary .paid-confirm-closed", text: "I paid", count: 3
    assert_select "#owed", text: /\$100\.00/
  end

  test "a paid row says when it was paid instead of offering the button" do
    participants(:dinner_marissa).update!(paid_at: Time.current)

    get share_url(splits(:dinner).share_token)

    assert_select "summary .paid-confirm-closed", text: "I paid", count: 2
    assert_select "##{ActionView::RecordIdentifier.dom_id(participants(:dinner_marissa))}",
                  text: /Paid/
    assert_select "#owed", text: /\$66\.66/
  end

  test "a fully paid split says so rather than showing a zero" do
    splits(:dinner).participants.each { |participant| participant.update!(paid_at: Time.current) }

    get share_url(splits(:dinner).share_token)

    assert_select "#owed", text: /Everyone has paid/
    assert_select "summary .paid-confirm-closed", text: "I paid", count: 0
  end

  # The share token is the only secret, so it must not be guessable from the id.
  test "a split cannot be opened by its id" do
    get share_url(splits(:dinner).id)

    assert_response :not_found
  end
end
