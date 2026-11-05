module ApplicationHelper
  # Only seeded fictional contacts get generated portraits; real contacts keep
  # their initials until an actual photo is available.
  def avatar_portrait_index(person)
    return unless person && DevelopmentContacts::CONTACTS[person.name] == person.phone_number && person.phone_number.present?

    DevelopmentContacts::NAMES.index(person.name)
  end

  # Stable initials and colors make a saved friend recognizable across screens.
  def avatar_initials(name)
    words = name.to_s.split
    [ words.first, words.size > 1 ? words.last : nil ].compact.map { |word| word[0] }.join.upcase
  end

  def avatar_tone(name)
    name.to_s.codepoints.sum % 5
  end
end
