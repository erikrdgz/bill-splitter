require "test_helper"

class DevelopmentContactsTest < ActiveSupport::TestCase
  test "preview is disabled outside development even when its local flag exists" do
    assert_not DevelopmentContacts.enabled?
    assert_no_difference -> { Person.count } do
      DevelopmentContacts.seed_for("preview-disabled")
    end
  end

  test "sample contacts remain separate for each browser and repeat safely" do
    DevelopmentContacts.populate("preview-first")
    DevelopmentContacts.populate("preview-second")
    first = Person.owned_by("preview-first")
    second = Person.owned_by("preview-second")
    assert_equal 8, first.count
    assert_equal 8, second.count
    assert_empty first.ids & second.ids
    assert_equal DevelopmentContacts::NAMES.sort, first.pluck(:name).sort
    assert(first.all? { |person| person.phone_number.present? })
    assert_equal "erik-r", PaymentProfile.for_owner("preview-first").venmo_handle
    assert_no_difference -> { Person.count } do
      DevelopmentContacts.populate("preview-first")
    end
  end
end
