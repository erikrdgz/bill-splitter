# Turns what a person types into whole cents, and cents back into something to
# read. The mirror of #amountInCents and #formattedDollars in
# quick_split_logic_controller.js — same rules, same results, on both sides.
#
# Like SplitMath this is plain Ruby with no table behind it, because it is a
# rule rather than a record.
class DollarAmount
  class << self
    # "100" -> 10000. "$1,234.56" -> 123456. ".5" -> 50.
    # Returns nil when there is no number in there at all, which is how the
    # quick split tells "nothing typed yet" from "zero".
    def to_cents(typed)
      digits = typed.to_s.gsub(/[^0-9.]/, "")
      return nil if digits.empty?

      whole_dollars, fraction = digits.split(".")

      # "#{fraction}00"[0, 2] pads and truncates in one step: "5" becomes "50",
      # "" becomes "00", and "567" becomes "56".
      whole_dollars.to_i * 100 + "#{fraction}00"[0, 2].to_i
    end

    # 123456 -> "$1,234.56". Built from the integer by divmod, so no float ever
    # touches money on the way to the screen either.
    def format(cents)
      whole_dollars, remainder = cents.to_i.abs.divmod(100)
      delimited = ActiveSupport::NumberHelper.number_to_delimited(whole_dollars)
      formatted = "$#{delimited}.#{remainder.to_s.rjust(2, '0')}"

      cents.to_i.negative? ? "-#{formatted}" : formatted
    end

    # 123456 -> "1234.56", for putting back into a form field. No currency sign
    # and no thousands delimiter, so what comes back out parses cleanly.
    def to_input(cents)
      return nil if cents.nil?

      whole_dollars, remainder = cents.to_i.divmod(100)

      "#{whole_dollars}.#{remainder.to_s.rjust(2, '0')}"
    end
  end
end
