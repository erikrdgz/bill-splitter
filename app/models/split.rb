# One bill being divided. A Split owns its Participants and is the thing that
# decides whether a set of amounts is allowed: every amount must add up to
# total_cents exactly, and that check lives here rather than in a controller so
# no request can skip it.
class Split < ApplicationRecord
  # validate: true makes a bad value a validation error rather than an
  # ArgumentError raised on assignment, which matters because split_mode arrives
  # from a form and a form can send anything.
  enum :split_mode, { even: "even", custom: "custom" }, validate: true

  # Fills share_token with a random, hard-to-guess string before insert, which
  # is the whole security model for the public share link.
  has_secure_token :share_token

  # autosave, because a split and its amounts are one thing. Re-spreading the
  # money changes every row, and saving the split without them would leave the
  # database holding a split that does not add up.
  has_many :participants, -> { order(:position) }, dependent: :destroy, autosave: true

  validates :title, presence: true, length: { maximum: 80 }
  validates :owner_token, presence: true
  validates :total_cents, numericality: {
    only_integer: true,
    greater_than: 0,
    less_than_or_equal_to: SplitMath::MAXIMUM_TOTAL_CENTS
  }
  validate :people_count_within_limits
  validate :total_covers_at_least_a_cent_each
  validate :participants_add_up_to_total

  scope :owned_by, ->(owner_token) { where(owner_token: owner_token) }
  scope :newest_first, -> { order(created_at: :desc) }

  # The total as a person types it. Forms deal in dollars; the database only
  # ever sees cents.
  def amount=(typed)
    self.total_cents = DollarAmount.to_cents(typed)
  end

  def amount
    DollarAmount.to_input(total_cents)
  end

  # Rule 2 applied to this split: every row gets an even share and no row is
  # locked. Assigns only — the caller saves.
  def apply_even_split
    shares = SplitMath.even_shares(total_cents: total_cents.to_i, people_count: participants.size)

    participants.each_with_index do |participant, index|
      participant.amount_cents = shares[index]
      participant.locked = false
    end
  end

  # Rule 3 applied to this split: locked rows keep what the organizer gave them,
  # and the rest share what is left. Assigns only — the caller saves.
  def apply_custom_split
    shares = SplitMath.custom_shares(
      total_cents: total_cents.to_i,
      locked_amounts: participants.map { |participant| participant.locked? ? participant.amount_cents.to_i : nil }
    )

    participants.each_with_index { |participant, index| participant.amount_cents = shares[index] }
  end

  # What the editor shows as "remaining". Added up in Ruby, not SQL, so it is
  # right for amounts the organizer has changed but not yet saved.
  def remaining_cents
    total_cents.to_i - participants.sum { |participant| participant.amount_cents.to_i }
  end

  # What history and the organizer's detail page show as still owed.
  def owed_cents
    participants.reject(&:paid?).sum { |participant| participant.amount_cents.to_i }
  end

  def fully_paid?
    participants.any? && participants.all?(&:paid?)
  end

  private

  # Participants the user is deleting in this same save should not count toward
  # any of the checks below.
  def live_participants
    participants.reject(&:marked_for_destruction?)
  end

  def people_count_within_limits
    return if SplitMath::PEOPLE_RANGE.cover?(live_participants.size)

    errors.add(:participants, "must be between #{SplitMath::PEOPLE_RANGE.min} " \
                              "and #{SplitMath::PEOPLE_RANGE.max} people")
  end

  # Rule 6: the total has to leave at least a cent for each person, otherwise an
  # even split would hand somebody nothing.
  def total_covers_at_least_a_cent_each
    return if total_cents.to_i >= live_participants.size

    errors.add(:total_cents, "must be at least one cent per person")
  end

  # The rule the whole app exists to keep. A split that does not add up is not
  # saved, whatever the browser believed.
  def participants_add_up_to_total
    return if live_participants.empty? # the count check above already said so

    difference = live_participants.sum { |participant| participant.amount_cents.to_i } - total_cents.to_i
    return if difference.zero?

    errors.add(:participants, "must add up to the total")
  end
end
