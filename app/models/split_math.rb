# The money rules from SPEC.md, gathered in one plain Ruby class.
#
# Why this is not an Active Record model: these rules need no database and no
# Rails. Keeping them here means they can be tested on their own, in
# milliseconds, over thousands of cases — and it gives the Stimulus controllers
# one definition to mirror in the browser. The browser only guesses for instant
# feedback; the server calls these methods and has the final say.
#
# Every amount here is whole cents. There is no floating-point money anywhere,
# because a float cannot hold $0.01 exactly, and a split that drifts by a cent
# is the one thing the spec says must never happen.
class SplitMath
  # Rule 6: limits.
  PEOPLE_RANGE = (2..20).freeze
  MAXIMUM_TOTAL_CENTS = 9_999_999 # $99,999.99

  class << self
    # Rule 2: even split. Each person gets total / people, rounded down, and the
    # leftover cents go one each to the first people in list order.
    #
    #   even_shares(total_cents: 10_000, people_count: 3) # => [3334, 3333, 3333]
    #
    # Returns an array of cents, in list order, that always sums to total_cents.
    def even_shares(total_cents:, people_count:)
      validate_total!(total_cents)
      raise ArgumentError, "people_count must be at least 1, got #{people_count}" if people_count < 1

      # divmod hands back the share and the leftover in one step, in integers,
      # so there is no rounding mode to get wrong.
      base_share, leftover_cents = total_cents.divmod(people_count)

      Array.new(people_count) do |index|
        index < leftover_cents ? base_share + 1 : base_share
      end
    end

    # Rule 3: custom split. A row the organizer has set keeps its amount and
    # locks; what is left of the total spreads evenly over the unlocked rows
    # using rule 2.
    #
    # +locked_amounts+ is position-aligned with the participant list: an integer
    # for a locked row, nil for a row that should absorb what is left.
    #
    #   custom_shares(total_cents: 10_000, locked_amounts: [5000, nil, nil])
    #   # => [5000, 2500, 2500]
    #
    # Two edges worth knowing:
    # - If the locked rows already come to more than the total, the unlocked rows
    #   get 0 rather than a negative amount. The result then does not add up, and
    #   Split's validation is what reports that to the organizer.
    # - If every row is locked, the amounts are handed back untouched. There is
    #   no unlocked row left to absorb a difference, so again Split decides
    #   whether the split is valid.
    def custom_shares(total_cents:, locked_amounts:)
      validate_total!(total_cents)
      raise ArgumentError, "locked_amounts cannot be empty" if locked_amounts.empty?
      if locked_amounts.compact.any?(&:negative?)
        raise ArgumentError, "a locked amount cannot be negative, got #{locked_amounts.inspect}"
      end

      unlocked_count = locked_amounts.count(&:nil?)
      return locked_amounts.dup if unlocked_count.zero?

      # [..., 0].max is what keeps an unlocked row from ever going negative.
      remaining_cents = [ total_cents - locked_amounts.compact.sum, 0 ].max
      unclaimed_shares = even_shares(total_cents: remaining_cents, people_count: unlocked_count)

      locked_amounts.map { |locked_amount| locked_amount || unclaimed_shares.shift }
    end

    # Rule 4: slider limit. A row can never claim cents another row already
    # holds — locked or not. That is what stops the amounts adding up to more
    # than the total while the organizer is allocating by hand.
    #
    # It counts every other row, not only the locked ones, because in custom
    # mode an untouched row keeps whatever it was last given rather than being
    # re-evened out from under the organizer.
    def maximum_for_row(total_cents:, other_amounts:)
      validate_total!(total_cents)

      [ total_cents - other_amounts.sum, 0 ].max
    end

    # Rule 5: percentages are display only, worked out from cents, one decimal.
    # Cents stay the source of truth, so these are never added back up.
    def percentage_of(amount_cents:, total_cents:)
      return 0.0 if total_cents.to_i.zero?

      (amount_cents * 100.0 / total_cents).round(1)
    end

    private

    def validate_total!(total_cents)
      raise ArgumentError, "total_cents cannot be negative, got #{total_cents}" if total_cents.negative?
    end
  end
end
