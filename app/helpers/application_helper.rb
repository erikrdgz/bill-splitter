module ApplicationHelper
  # Stable initials and colors make a saved friend recognizable across screens.
  def avatar_initials(name)
    words = name.to_s.split
    [ words.first, words.size > 1 ? words.last : nil ].compact.map { |word| word[0] }.join.upcase
  end

  def avatar_tone(name)
    name.to_s.codepoints.sum % 5
  end
end
