# A name the organizer has saved, so they never type "Marissa" twice.
# People belong to a browser, not an account: owner_token comes from a signed
# cookie set on the first visit.
class Person < ApplicationRecord
  # Where this person can be asked for money, if the organizer knows.
  include PaymentHandles

  # :nullify, not :destroy. Deleting a person must not quietly delete a row from
  # a past split and make its amounts stop adding up; the row falls back to its
  # "Person 3" placeholder instead.
  has_many :participants, dependent: :nullify

  validates :name, presence: true, length: { maximum: 40 },
                   uniqueness: { scope: :owner_token, case_sensitive: false }
  validates :owner_token, presence: true

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
