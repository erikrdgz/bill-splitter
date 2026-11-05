require "test_helper"

# PaymentProfile is the simpler of the two models that include PaymentHandles,
# so the concern's own rules are tested here. Person's test covers that it gets
# them too.
class PaymentProfileTest < ActiveSupport::TestCase
  test "a profile needs an owner token and there is only one per browser" do
    assert_not PaymentProfile.new.valid?

    PaymentProfile.create!(owner_token: "a-browser")

    assert_not PaymentProfile.new(owner_token: "a-browser").valid?
  end

  test "for_owner finds the profile, or builds one rather than returning nil" do
    assert_predicate PaymentProfile.for_owner("nobody-yet"), :new_record?
    assert_equal payment_profiles(:organizer), PaymentProfile.for_owner("organizer-token")
  end

  # People type the handle the way they see it written.

  test "a leading at sign is dropped from a Venmo username" do
    assert_equal "marissa-v", build(venmo_handle: "@marissa-v").venmo_handle
  end

  test "a leading dollar sign is dropped from a cashtag" do
    assert_equal "marissa", build(cashapp_cashtag: "$marissa").cashapp_cashtag
  end

  test "surrounding whitespace is dropped" do
    assert_equal "marissa", build(venmo_handle: "  marissa  ").venmo_handle
  end

  test "a blank handle becomes nil, so nothing downstream sees an empty string" do
    profile = build(venmo_handle: "", cashapp_cashtag: "  ")

    assert_nil profile.venmo_handle
    assert_nil profile.cashapp_cashtag
    assert_not profile.any_payment_handle?
  end

  # Every one of these ends up inside a URL, so the format is checked rather
  # than trusted.

  test "a Venmo username may only hold letters, digits, dashes and underscores" do
    assert build(venmo_handle: "marissa-v_1").valid?
    assert_not build(venmo_handle: "marissa v").valid?
    assert_not build(venmo_handle: "marissa/../etc").valid?
    assert_not build(venmo_handle: "a" * 31).valid?
  end

  test "a cashtag must start with a letter" do
    assert build(cashapp_cashtag: "marissa1").valid?
    assert_not build(cashapp_cashtag: "1marissa").valid?
    assert_not build(cashapp_cashtag: "marissa-v").valid?
  end

  test "a bad handle says which one it is" do
    profile = build(venmo_handle: "not a username")

    assert_not profile.valid?
    assert_includes profile.errors[:venmo_handle], "is not a Venmo username"
  end

  # What the screens ask.

  test "handle_for keeps callers from knowing which column belongs to which app" do
    profile = payment_profiles(:organizer)

    assert_equal "erik-r", profile.handle_for(:venmo)
    assert_equal "erikr", profile.handle_for(:cash_app)
    assert_nil profile.handle_for(:zelle)
    assert_nil profile.handle_for(:apple_pay)
  end

  test "any_payment_handle? is true as soon as one is set" do
    assert_not build.any_payment_handle?
    assert build(cashapp_cashtag: "marissa").any_payment_handle?
  end

  private

  def build(**attributes)
    PaymentProfile.new({ owner_token: "a-browser" }.merge(attributes))
  end
end
