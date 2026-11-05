module MoneyHelper
  # Every amount on every screen goes through here, so money is formatted one
  # way and from integers only.
  def money(cents)
    DollarAmount.format(cents)
  end
end
