# One person's share of one split. It may point at a saved Person, or stay an
# unnamed placeholder the spec shows as "Person 3".
class Participant < ApplicationRecord
  belongs_to :split
  belongs_to :person, optional: true

  # position is 1-based: it sets list order, decides who gets the leftover cent
  # under rule 2, and names the placeholder.
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :unpaid, -> { where(paid_at: nil) }
  scope :paid, -> { where.not(paid_at: nil) }

  def display_name
    person&.name || "Person #{position}"
  end

  def paid?
    paid_at.present?
  end

  # Display only, per rule 5. Never added back up — cents are the source of truth.
  def percentage
    SplitMath.percentage_of(amount_cents: amount_cents.to_i, total_cents: split&.total_cents)
  end
end
