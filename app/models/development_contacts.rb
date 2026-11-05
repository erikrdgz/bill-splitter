# Opt-in fixture data for local UI review. Every browser gets its own records;
# ownership and real contact lists are never shared between browser sessions.
class DevelopmentContacts
  NAMES = [ "Maya Chen", "Jordan Lee", "Sam Taylor", "Priya Shah", "Chris Park", "Nina Patel", "Mateo Cruz", "Alex Rivera" ].freeze

  def self.flag_path
    Rails.root.join("tmp/contact-preview.txt")
  end

  def self.enabled?
    Rails.env.development? && flag_path.exist?
  end

  def self.seed_for(owner_token)
    return unless enabled?
    return if Person.owned_by(owner_token).exists?

    populate(owner_token)
  end

  def self.populate(owner_token)
    Person.transaction do
      NAMES.each { |name| Person.find_or_create_by!(owner_token: owner_token, name: name) }
    end
  end
end
