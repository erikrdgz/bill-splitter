require "test_helper"

class DollarAmountTest < ActiveSupport::TestCase
  test "plain dollars become cents" do
    assert_equal 10_000, DollarAmount.to_cents("100")
    assert_equal 10_050, DollarAmount.to_cents("100.5")
    assert_equal 10_001, DollarAmount.to_cents("100.01")
  end

  test "whatever people actually type becomes cents" do
    assert_equal 123_456, DollarAmount.to_cents("$1,234.56")
    assert_equal 50, DollarAmount.to_cents(".5")
    assert_equal 10_000, DollarAmount.to_cents("  100  ")
    assert_equal 10_000, DollarAmount.to_cents("100 dollars")
  end

  test "more than two decimal places are truncated, not rounded" do
    # Rounding up would invent a cent nobody agreed to pay.
    assert_equal 10_099, DollarAmount.to_cents("100.999")
  end

  test "nothing to parse means nil, which is how nothing typed is told from zero" do
    assert_nil DollarAmount.to_cents("")
    assert_nil DollarAmount.to_cents(nil)
    assert_nil DollarAmount.to_cents("abc")
    assert_equal 0, DollarAmount.to_cents("0")
  end

  test "cents are formatted for reading" do
    assert_equal "$33.34", DollarAmount.format(3334)
    assert_equal "$0.05", DollarAmount.format(5)
    assert_equal "$1,234.56", DollarAmount.format(123_456)
    assert_equal "$99,999.99", DollarAmount.format(SplitMath::MAXIMUM_TOTAL_CENTS)
  end

  test "a negative amount keeps its sign outside the currency symbol" do
    assert_equal "-$1.50", DollarAmount.format(-150)
  end

  test "cents are formatted for a form field without a symbol or delimiter" do
    assert_equal "1234.56", DollarAmount.to_input(123_456)
    assert_equal "0.05", DollarAmount.to_input(5)
    assert_nil DollarAmount.to_input(nil)
  end

  test "what the form shows parses back to the same cents" do
    [ 1, 5, 99, 100, 3334, 123_456, SplitMath::MAXIMUM_TOTAL_CENTS ].each do |cents|
      assert_equal cents, DollarAmount.to_cents(DollarAmount.to_input(cents)),
                   "#{cents} did not survive the round trip"
    end
  end

  test "what the screen shows parses back to the same cents too" do
    [ 1, 3334, 123_456, SplitMath::MAXIMUM_TOTAL_CENTS ].each do |cents|
      assert_equal cents, DollarAmount.to_cents(DollarAmount.format(cents)),
                   "#{cents} did not survive the round trip"
    end
  end
end
