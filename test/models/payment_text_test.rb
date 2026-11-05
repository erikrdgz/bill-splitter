require "test_helper"

class PaymentTextTest < ActiveSupport::TestCase
  setup do
    @split = Split.new(title: "Dinner & drinks", total_cents: 10_000, owner_token: "t")
    @profile = PaymentProfile.new(owner_token: "t", venmo_handle: "erik-r", cashapp_cashtag: "erikr")
  end

  test "the body greets by first name and links to the organizer, not the friend" do
    text = build(method: "venmo", phone: "5555550101")

    assert_equal "Hi Maya, your share of Dinner & drinks is $33.34. Pay with Venmo: " \
                 "https://venmo.com/erik-r?amount=33.34&note=Dinner+%26+drinks&txn=pay", text.body
  end

  test "the body ends with the share page so the friend can mark themselves paid" do
    text = build(method: "venmo", phone: "5555550101", share_url: "https://example.com/s/abc")

    assert text.body.end_with?(" Then tap I paid here: https://example.com/s/abc")
  end

  test "the sms link is encoded so the link inside the message survives" do
    url = build(method: "cash_app", phone: "5555550101").sms_url

    assert url.start_with?("sms:+15555550101?&body=")
    assert_not_includes url, " "
    assert_includes CGI.unescape(url), "https://cash.app/$erikr/33.34"
  end

  test "blockers are reported in the order a person would fix them" do
    assert_equal :no_person, build(method: "venmo", person: false).blocker
    assert_equal :cash, build(method: "cash", phone: "5555550101").blocker
    assert_equal :no_phone, build(method: "venmo").blocker
    assert_equal :no_organizer_handle, build(method: "venmo", phone: "5555550101", profile: PaymentProfile.new).blocker
    assert_predicate build(method: "venmo", phone: "5555550101"), :sendable?
  end

  private

  def build(method:, phone: nil, person: true, profile: @profile, share_url: nil)
    participant = Participant.new(position: 1, amount_cents: 3334, payment_method: method,
                                  person: (Person.new(name: "Maya Chen", phone_number: phone) if person))
    PaymentText.new(participant: participant, split: @split, payment_profile: profile, share_url: share_url)
  end
end
