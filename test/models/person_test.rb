require "test_helper"

class PersonTest < ActiveSupport::TestCase
  test "a person needs a name of at most forty characters" do
    assert_not build_person(name: "").valid?
    assert_not build_person(name: "x" * 41).valid?
    assert build_person(name: "x" * 40).valid?
  end

  test "a person needs an owner token, because that is whose list they are on" do
    assert_not build_person(owner_token: nil).valid?
  end

  test "one browser cannot save the same name twice, whatever the casing" do
    assert_not build_person(name: "Marissa").valid?
    assert_not build_person(name: "marissa").valid?
    assert_not build_person(name: "MARISSA").valid?
  end

  test "two browsers may each save a person of the same name" do
    assert build_person(name: "Marissa", owner_token: "a-third-browser-token").valid?
  end

  # The people picker.

  test "matching narrows to names containing the query, ignoring case" do
    names = Person.owned_by("organizer-token").matching("ma").by_name.pluck(:name)

    assert_equal [ "Marcus", "Marissa" ], names
  end

  test "matching ignores the case of the saved name too" do
    Person.create!(name: "dana's roommate", owner_token: "organizer-token")

    assert_includes Person.owned_by("organizer-token").matching("DANA").pluck(:name),
                    "dana's roommate"
  end

  test "matching on a blank query shows everyone on that browser's list" do
    assert_equal 3, Person.owned_by("organizer-token").matching("").count
    assert_equal 3, Person.owned_by("organizer-token").matching(nil).count
  end

  test "matching finds nothing when nothing matches" do
    assert_empty Person.owned_by("organizer-token").matching("zzz")
  end

  test "matching treats a percent sign as a character, not a wildcard" do
    # Without sanitize_sql_like this query would match every saved name.
    assert_empty Person.owned_by("organizer-token").matching("%")
  end

  test "matching stays inside one browser's list" do
    assert_equal 1, Person.owned_by("other-browser-token").matching("ma").count
  end

  # Deleting a person must not break a past split.

  test "deleting a person leaves their rows in place as placeholders" do
    person = people(:marissa)
    participant = participants(:dinner_marissa)

    assert_no_difference -> { Participant.count } do
      person.destroy!
    end
    assert_nil participant.reload.person
    assert_equal "Person 1", participant.display_name
    assert_equal 10_000, splits(:dinner).reload.owed_cents
  end

  private

  def build_person(name: "Someone new", owner_token: "organizer-token")
    Person.new(name: name, owner_token: owner_token)
  end

  # The phone number a request is texted to.

  test "phone numbers are stored in one international form" do
    { "(555) 555-0101" => "+15555550101", "555.555.0101" => "+15555550101",
      "1 555 555 0101" => "+15555550101", "+44 20 7946 0958" => "+442079460958" }.each do |typed, stored|
      assert_equal stored, Person.new(name: "A", owner_token: "t", phone_number: typed).phone_number
    end
  end

  test "a blank phone number becomes nil and anything else must be a real shape" do
    assert_nil Person.new(name: "A", owner_token: "t", phone_number: "  ").phone_number
    assert_not Person.new(name: "A", owner_token: "t", phone_number: "12345").valid?
    assert_not Person.new(name: "A", owner_token: "t", phone_number: "call me").valid?
  end

  test "a US number is displayed the way people write it" do
    assert_equal "(555) 555-0101", Person.new(phone_number: "5555550101").display_phone_number
  end
end
