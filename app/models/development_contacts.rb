# Opt-in fixture data for local UI review. Every browser gets its own records;
# ownership and real contact lists are never shared between browser sessions.
class DevelopmentContacts
  # 555-01xx numbers are reserved for fiction, so a text to one can never reach a
  # real person while we are testing.
  CONTACTS = {
    "Maya Chen" => "+15555550101", "Jordan Lee" => "+15555550102", "Sam Taylor" => "+15555550103",
    "Priya Shah" => "+15555550104", "Chris Park" => "+15555550105", "Nina Patel" => "+15555550106",
    "Mateo Cruz" => "+15555550107", "Alex Rivera" => "+15555550108"
  }.freeze
  NAMES = CONTACTS.keys.freeze
  # The organizer's own fake handles, so a request has somewhere to point.
  ORGANIZER_HANDLES = { venmo_handle: "erik-r", cashapp_cashtag: "erikr" }.freeze

  def self.flag_path
    Rails.root.join("tmp/contact-preview.txt")
  end

  def self.enabled?
    Rails.env.development? && flag_path.exist?
  end

  def self.seed_for(owner_token)
    return unless enabled?
    people = Person.owned_by(owner_token)
    # Also backfills browsers seeded before phone numbers existed.
    return if people.exists? && people.where(phone_number: nil).none?

    populate(owner_token)
  end

  def self.populate(owner_token)
    Person.transaction do
      CONTACTS.each do |name, phone_number|
        person = Person.find_or_create_by!(owner_token: owner_token, name: name)
        person.update!(phone_number: phone_number) if person.phone_number.blank?
      end
      profile = PaymentProfile.for_owner(owner_token)
      profile.update!(ORGANIZER_HANDLES) unless profile.any_payment_handle?
    end
  end
end
