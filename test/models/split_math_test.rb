require "test_helper"

# SplitMath needs no database, so these tests build nothing and run in
# milliseconds. That is the point of keeping the rules in a plain Ruby class.
class SplitMathTest < ActiveSupport::TestCase
  # Rule 2: even split.

  test "an even split gives the leftover cents to the first people in list order" do
    assert_equal [ 3334, 3333, 3333 ], SplitMath.even_shares(total_cents: 10_000, people_count: 3)
  end

  test "an even split that divides cleanly gives everyone the same share" do
    assert_equal [ 2500, 2500, 2500, 2500 ], SplitMath.even_shares(total_cents: 10_000, people_count: 4)
  end

  test "an even split of a total smaller than the head count still adds up" do
    # Two cents between three people: two get a cent, one gets nothing. Split's
    # own validation is what stops a total this small from being saved.
    assert_equal [ 1, 1, 0 ], SplitMath.even_shares(total_cents: 2, people_count: 3)
  end

  test "an even split of the largest allowed total adds up" do
    shares = SplitMath.even_shares(total_cents: SplitMath::MAXIMUM_TOTAL_CENTS, people_count: 20)

    assert_equal SplitMath::MAXIMUM_TOTAL_CENTS, shares.sum
  end

  # The spec's property test: for 1,000 random totals and head counts, the
  # shares always add up to the total. The seed is fixed so a failure can be
  # reproduced exactly instead of only on an unlucky run.
  test "even shares always add up to the total, over a thousand random splits" do
    random = Random.new(20_261_105)

    1_000.times do
      total_cents = random.rand(1..SplitMath::MAXIMUM_TOTAL_CENTS)
      people_count = random.rand(SplitMath::PEOPLE_RANGE)
      shares = SplitMath.even_shares(total_cents: total_cents, people_count: people_count)
      context = "total #{total_cents} across #{people_count} people gave #{shares.inspect}"

      assert_equal total_cents, shares.sum, context
      assert_equal people_count, shares.size, context
      assert_not shares.any?(&:negative?), context
      # Nobody pays more than a cent above anybody else.
      assert_operator shares.max - shares.min, :<=, 1, context
    end
  end

  test "even shares refuse a negative total" do
    assert_raises(ArgumentError) { SplitMath.even_shares(total_cents: -1, people_count: 2) }
  end

  test "even shares refuse a head count below one" do
    assert_raises(ArgumentError) { SplitMath.even_shares(total_cents: 10_000, people_count: 0) }
  end

  # Rule 3: custom split.

  test "a custom split spreads what is left evenly over the unlocked rows" do
    assert_equal [ 5000, 2500, 2500 ],
                 SplitMath.custom_shares(total_cents: 10_000, locked_amounts: [ 5000, nil, nil ])
  end

  test "a custom split gives the leftover cent to the first unlocked row" do
    # $80.01 with $40.00 locked leaves 4001 cents for two rows.
    assert_equal [ 4000, 2001, 2000 ],
                 SplitMath.custom_shares(total_cents: 8001, locked_amounts: [ 4000, nil, nil ])
  end

  test "a custom split hands the last unlocked row exactly what is left" do
    assert_equal [ 6000, 3000, 1000 ],
                 SplitMath.custom_shares(total_cents: 10_000, locked_amounts: [ 6000, 3000, nil ])
  end

  test "a custom split never gives an unlocked row a negative amount" do
    # The locked row alone is already more than the total. The unlocked rows go
    # to zero, and the result deliberately does not add up: Split's validation
    # is what tells the organizer the split is over.
    shares = SplitMath.custom_shares(total_cents: 5000, locked_amounts: [ 9000, nil, nil ])

    assert_equal [ 9000, 0, 0 ], shares
    assert_not shares.any?(&:negative?)
  end

  test "a custom split leaves every row alone when all of them are locked" do
    assert_equal [ 6000, 3000, 1000 ],
                 SplitMath.custom_shares(total_cents: 10_000, locked_amounts: [ 6000, 3000, 1000 ])
  end

  test "custom shares add up to the total whenever the locked rows leave room" do
    random = Random.new(20_261_106)

    1_000.times do
      total_cents = random.rand(1..SplitMath::MAXIMUM_TOTAL_CENTS)
      people_count = random.rand(SplitMath::PEOPLE_RANGE)
      locked_count = random.rand(0...people_count)
      # Lock rows at amounts that together can never exceed the total, so there
      # is always room left for the unlocked rows.
      room_each = total_cents / (people_count * 2)
      locked_amounts = Array.new(people_count) do |index|
        index < locked_count ? random.rand(0..room_each) : nil
      end

      shares = SplitMath.custom_shares(total_cents: total_cents, locked_amounts: locked_amounts)
      context = "total #{total_cents} with locks #{locked_amounts.inspect} gave #{shares.inspect}"

      assert_equal total_cents, shares.sum, context
      assert_not shares.any?(&:negative?), context
      # Locked rows come back untouched.
      locked_amounts.each_with_index do |locked_amount, index|
        assert_equal locked_amount, shares[index], context if locked_amount
      end
    end
  end

  test "custom shares refuse a negative locked amount" do
    assert_raises(ArgumentError) do
      SplitMath.custom_shares(total_cents: 10_000, locked_amounts: [ -1, nil ])
    end
  end

  test "custom shares refuse an empty row list" do
    assert_raises(ArgumentError) { SplitMath.custom_shares(total_cents: 10_000, locked_amounts: []) }
  end

  # Rule 5: percentages are display only.

  test "a percentage is worked out from cents and rounded to one decimal" do
    assert_equal 33.3, SplitMath.percentage_of(amount_cents: 3334, total_cents: 10_000)
    assert_equal 50.0, SplitMath.percentage_of(amount_cents: 5000, total_cents: 10_000)
  end

  test "a percentage of a total of nothing is zero rather than a crash" do
    assert_equal 0.0, SplitMath.percentage_of(amount_cents: 0, total_cents: 0)
    assert_equal 0.0, SplitMath.percentage_of(amount_cents: 100, total_cents: nil)
  end
end
