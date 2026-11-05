require "test_helper"

class ParticipantTest < ActiveSupport::TestCase
  test "a participant pointing at a saved person shows that person's name" do
    assert_equal "Marissa", participants(:dinner_marissa).display_name
  end

  test "a participant with no person shows a placeholder named from its position" do
    assert_equal "Person 3", participants(:dinner_placeholder).display_name
  end

  test "a participant may exist without a person" do
    assert_nil participants(:dinner_placeholder).person
    assert_predicate participants(:dinner_placeholder), :valid?
  end

  test "a participant is unpaid until paid_at is set" do
    participant = participants(:dinner_marissa)

    assert_not participant.paid?

    participant.update!(paid_at: Time.current)

    assert_predicate participant, :paid?
  end

  test "the paid and unpaid scopes split a split's rows between them" do
    participants(:dinner_marissa).update!(paid_at: Time.current)
    split = splits(:dinner)

    assert_equal [ "Marissa" ], split.participants.paid.map(&:display_name)
    assert_equal [ "Marcus", "Person 3" ], split.participants.unpaid.map(&:display_name)
  end

  test "a percentage is worked out from the split's total" do
    assert_equal 33.3, participants(:dinner_marissa).percentage
  end

  test "a percentage does not crash on a participant with no split yet" do
    assert_equal 0.0, Participant.new(amount_cents: 100).percentage
  end

  test "a participant amount cannot be negative" do
    participant = participants(:dinner_marissa)
    participant.amount_cents = -1

    assert_not participant.valid?
    assert participant.errors[:amount_cents].any?
  end

  test "a participant position must be one or more" do
    participant = participants(:dinner_marissa)
    participant.position = 0

    assert_not participant.valid?
    assert participant.errors[:position].any?
  end

  test "two participants in one split cannot share a position" do
    duplicate = participants(:dinner_marissa).dup
    duplicate.person = nil

    # No model validation covers this: the unique index is what holds the line,
    # and a position collision is a bug rather than something to show a user.
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "a participant must belong to a split" do
    assert_not Participant.new(position: 1, amount_cents: 100).valid?
  end
end
