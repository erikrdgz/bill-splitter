# A draft can be calculated without records. Only an explicit save persists its
# connections and amounts, together, so invalid requests leave no orphan people.
class SplitDraft
  def initialize(split, rows)
    @split = split
    @rows = rows
  end

  def save
    saved = false
    Split.transaction do
      # Editing replaces the rows wholesale; the only thing a row carries that
      # the form cannot is whether it has been paid, so remember that by id.
      paid_times = @split.participants.to_h { |participant| [ participant.id.to_s, participant.paid_at ] }
      @split.participants.destroy_all if @split.persisted?
      @split.split_mode = @rows.any? { |row| row[:locked] == "1" } ? :custom : :even
      @rows.first(SplitMath::PEOPLE_RANGE.max + 1).each_with_index do |row, index|
        person = connected_person(row)
        @split.participants.build(position: index + 1, person: person,
          amount_cents: row[:amount_cents], locked: row[:locked] == "1",
          payment_method: row[:payment_method].presence, paid_at: paid_times[row[:id].to_s])
      end
      @split.apply_even_split if @split.even?
      valid_split = @split.valid?
      # Cash counts, but a row nobody has connected has no way to be asked.
      unconnected = @rows.any? { |row| row[:payment_method].blank? }
      @split.errors.add(:base, "Connect everyone before saving") if unconnected
      people = @split.participants.map(&:person).compact.uniq
      valid_people = people.map do |person|
        person.valid?.tap do |valid|
          person.errors.full_messages.each { |message| @split.errors.add(:base, "#{person.name}: #{message}") } unless valid
        end
      end.all?
      raise ActiveRecord::Rollback unless valid_split && valid_people && !unconnected

      people.each(&:save!)
      saved = @split.save
      raise ActiveRecord::Rollback unless saved
    end
    saved
  end

  private

  def connected_person(row)
    scope = Person.owned_by(@split.owner_token)
    person = if row[:person_id].present?
      scope.find(row[:person_id])
    elsif row[:name].present?
      name = row[:name].strip
      @named_people ||= {}
      @named_people[name.downcase] ||= scope.find_by("LOWER(name) = ?", name.downcase) || scope.new(name: name)
    end
    person.phone_number = row[:phone_number] if person && row[:phone_number].present?
    person
  end
end
