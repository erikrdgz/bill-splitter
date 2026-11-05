# Where the organizer gets paid. One per browser, found by the same signed
# cookie that owns their splits and their saved people.
class PaymentProfile < ApplicationRecord
  include PaymentHandles

  validates :owner_token, presence: true, uniqueness: true

  # Every organizer has one as soon as they need one, so nothing downstream has
  # to cope with nil.
  def self.for_owner(owner_token)
    find_or_initialize_by(owner_token: owner_token)
  end
end
