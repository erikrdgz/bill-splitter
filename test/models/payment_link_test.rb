require "test_helper"

class PaymentLinkTest < ActiveSupport::TestCase
  # Venmo: real links, both directions.

  test "a Venmo request opens Venmo asking for the amount" do
    link = build(app: :venmo, handle: "marissa-v", amount_cents: 3334,
                 note: "Dinner at Rosalia", direction: :charge)

    assert_predicate link, :real?
    assert_equal "https://venmo.com/marissa-v?amount=33.34&note=Dinner+at+Rosalia&txn=charge",
                 link.url
  end

  test "a Venmo payment opens Venmo sending the amount" do
    link = build(app: :venmo, handle: "erik", amount_cents: 5000, note: "Taxi", direction: :pay)

    assert_includes link.url, "txn=pay"
    assert_includes link.url, "amount=50.00"
  end

  test "the amount in a link is plain dollars, with no sign and no delimiter" do
    link = build(app: :venmo, handle: "erik", amount_cents: 123_456)

    assert_includes link.url, "amount=1234.56"
  end

  # Cash App: real one way only.

  test "a Cash App payment is a real link" do
    link = build(app: :cash_app, handle: "erikr", amount_cents: 3334, direction: :pay)

    assert_predicate link, :real?
    assert_equal "https://cash.app/$erikr/33.34", link.url
  end

  # Cash App links send money; they cannot ask for it.
  test "a Cash App request is a demonstration, not a link" do
    link = build(app: :cash_app, handle: "erikr", amount_cents: 3334, direction: :charge)

    assert_not_predicate link, :real?
    assert_nil link.url
    assert_match "cannot ask for it", link.why_demonstrated
  end

  # Zelle and Apple Pay: never real, and they say why.

  test "Zelle is a demonstration because it has no public link format" do
    link = build(app: :zelle, handle: "erik@example.com", amount_cents: 3334)

    assert_not_predicate link, :real?
    assert_nil link.url
    assert_match "bank", link.why_demonstrated
  end

  test "Apple Pay is a demonstration because it needs a merchant account" do
    link = build(app: :apple_pay, handle: "erik@example.com", amount_cents: 3334)

    assert_not_predicate link, :real?
    assert_nil link.url
    assert_match "merchant account", link.why_demonstrated
  end

  # Nothing is claimed about a handle nobody has given.

  test "a missing handle is never a real link" do
    PaymentLink::APPS.each do |app|
      link = build(app: app, handle: nil, amount_cents: 3334)

      assert_not_predicate link, :real?, "#{app} claimed to be real without a handle"
      assert_equal "(not set)", link.display_handle
    end
  end

  # Handles end up inside URLs, so they are escaped on the way out as well as
  # validated on the way in.

  test "a handle is escaped into the URL" do
    link = build(app: :venmo, handle: "a b&c=d", amount_cents: 100)

    assert_includes link.url, "https://venmo.com/a%20b%26c%3Dd?"
    assert_not_includes link.url, "venmo.com/a b&c=d"
  end

  test "a note is escaped into the URL" do
    link = build(app: :venmo, handle: "erik", amount_cents: 100, note: "Drinks & chips?")

    assert_includes link.url, "note=Drinks+%26+chips%3F"
  end

  # What the interface shows.

  test "a handle is displayed the way its app writes it" do
    assert_equal "@marissa", build(app: :venmo, handle: "marissa", amount_cents: 1).display_handle
    assert_equal "$marissa", build(app: :cash_app, handle: "marissa", amount_cents: 1).display_handle
    assert_equal "m@example.com",
                 build(app: :zelle, handle: "m@example.com", amount_cents: 1).display_handle
  end

  test "a summary says who is being asked for what, and where" do
    assert_equal "Request $33.34 from @marissa on Venmo",
                 build(app: :venmo, handle: "marissa", amount_cents: 3334,
                       direction: :charge).summary
    assert_equal "Pay $33.34 to $erikr on Cash App",
                 build(app: :cash_app, handle: "erikr", amount_cents: 3334, direction: :pay).summary
  end

  test "an unknown app or direction is refused rather than silently ignored" do
    assert_raises(ArgumentError) { build(app: :paypal, handle: "erik", amount_cents: 1) }
    assert_raises(ArgumentError) do
      build(app: :venmo, handle: "erik", amount_cents: 1, direction: :sideways)
    end
  end

  private

  def build(app:, handle:, amount_cents:, note: nil, direction: :pay)
    PaymentLink.new(app: app, handle: handle, amount_cents: amount_cents,
                    note: note, direction: direction)
  end
end
