# A name the organizer has saved, so they never type "Marissa" twice.
# People belong to a browser, not an account: owner_token comes from a signed
# cookie set on the first visit.
class Person < ApplicationRecord
  # :nullify, not :destroy. Deleting a person must not quietly delete a row from
  # a past split and make its amounts stop adding up; the row falls back to its
  # "Person 3" placeholder instead.
  has_many :participants, dependent: :nullify

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: :owner_token, case_sensitive: false }
  validates :owner_token, presence: true

  # Where a request is texted. Stored as E.164 (+15551230101) so the sms: link
  # works the same on every phone, whatever the organizer typed. Bare US numbers
  # get +1 because this is a US-first product; anything else must say its code.
  normalizes :phone_number, with: ->(raw) {
    # Only punctuation is stripped, so letters survive to fail validation
    # instead of "call me" quietly becoming no number at all.
    digits = raw.gsub(/[\s().-]/, "")
    digits = "+1#{digits}" if digits.match?(/\A\d{10}\z/)
    digits = "+#{digits}" if digits.match?(/\A1\d{10}\z/)
    digits.presence
  }
  validates :phone_number, format: { with: /\A\+[1-9]\d{7,14}\z/, message: "is not a phone number" },
                           allow_nil: true

  # Shown as (555) 123-0101 for US numbers; anything else is shown as stored.
  def display_phone_number
    return if phone_number.blank?

    phone_number.sub(/\A\+1(\d{3})(\d{3})(\d{4})\z/, '(\1) \2-\3')
  end

  scope :owned_by, ->(owner_token) { where(owner_token: owner_token) }
  # Most recently connected first, including people not used in a split yet.
  scope :recently_used, -> {
    left_joins(:participants).group(:id)
      .order(Arel.sql("COALESCE(MAX(participants.updated_at), people.created_at) DESC, people.id DESC"))
  }

  scope :by_name, -> { order(:name) }

  # Search-as-you-type for the people picker. A class method rather than a scope
  # so sanitize_sql_like resolves plainly, and LOWER() keeps the match
  # case-insensitive on SQLite now and on Postgres later.
  #
  # A blank query means "show me everyone", which is what the picker wants
  # before the organizer has typed anything.
  def self.matching(query)
    query = query.to_s.strip
    return all if query.blank?

    where("LOWER(name) LIKE ?", "%#{sanitize_sql_like(query.downcase)}%")
  end
end
