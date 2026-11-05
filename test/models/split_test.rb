require "test_helper"

class SplitTest < ActiveSupport::TestCase
  test "a split with shares that add up is valid" do
    assert build_even_split.valid?
  end

  test "a saved split always has a share token" do
    split = build_even_split

    assert split.save
    assert split.reload.share_token.present?
  end

  # Worth knowing rather than guessing: under Rails 7.1+ framework defaults,
  # has_secure_token fills the column on `new`, not in a before_create callback.
  # So the share link exists before the record does, and nothing needs to
  # reload a split just to read its token.
  test "a share token is generated as soon as a split is built" do
    assert Split.new.share_token.present?
  end

  test "share tokens differ between splits and are long enough not to be guessed" do
    first = build_even_split
    second = build_even_split
    first.save!
    second.save!

    assert_not_equal first.share_token, second.share_token
    assert_operator first.share_token.length, :>=, 24
  end

  test "two splits cannot share a token" do
    duplicate = build_even_split
    duplicate.share_token = splits(:dinner).share_token

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end

  # The rule the whole app exists to keep.

  test "a split is invalid when the participants do not add up to the total" do
    split = build_even_split
    split.participants.first.amount_cents += 1

    assert_not split.valid?
    assert_includes split.errors[:participants], "must add up to the total"
  end

  test "a split is invalid when the participants add up to less than the total" do
    split = build_even_split
    split.participants.first.amount_cents -= 1

    assert_not split.valid?
    assert_includes split.errors[:participants], "must add up to the total"
  end

  test "the database refuses a participant amount below zero even without validations" do
    split = build_even_split
    split.save!

    assert_raises(ActiveRecord::StatementInvalid) do
      split.participants.first.update_column(:amount_cents, -1)
    end
  end

  # Rule 6: limits.

  test "a split is invalid with fewer than two people" do
    split = build_even_split(people_count: 1)

    assert_not split.valid?
    assert_includes split.errors[:participants], "must be between 2 and 20 people"
  end

  test "a split is invalid with more than twenty people" do
    split = build_even_split(people_count: 21)

    assert_not split.valid?
    assert_includes split.errors[:participants], "must be between 2 and 20 people"
  end

  test "a split is valid at both ends of the people range" do
    assert build_even_split(people_count: 2).valid?
    assert build_even_split(people_count: 20).valid?
  end

  test "a split is invalid when the total leaves somebody no cents at all" do
    split = build_even_split(total_cents: 2, people_count: 3)

    assert_not split.valid?
    assert_includes split.errors[:total_cents], "must be at least one cent per person"
  end

  test "a split is invalid above the largest allowed total" do
    split = build_even_split(total_cents: SplitMath::MAXIMUM_TOTAL_CENTS + 1)

    assert_not split.valid?
    assert split.errors[:total_cents].any?
  end

  test "a split is invalid with a total of zero" do
    split = Split.new(title: "Nothing", total_cents: 0, owner_token: "organizer-token")

    assert_not split.valid?
    assert split.errors[:total_cents].any?
  end

  # Other columns from the spec's table.

  test "a split needs a title of at most eighty characters" do
    assert_not build_even_split(title: "").valid?
    assert_not build_even_split(title: "x" * 81).valid?
    assert build_even_split(title: "x" * 80).valid?
  end

  test "a split needs an owner token, because that is who may edit it" do
    assert_not build_even_split(owner_token: nil).valid?
  end

  test "a split mode outside even and custom is reported, not raised" do
    split = build_even_split

    assert_nothing_raised { split.split_mode = "sideways" }
    assert_not split.valid?
    assert split.errors[:split_mode].any?
  end

  test "a new split starts in even mode" do
    assert_predicate Split.new, :even?
  end

  # Applying the math.

  test "apply_even_split gives every row a rule 2 share and clears the locks" do
    split = build_even_split(total_cents: 10_000, people_count: 3, apply_math: false)
    split.participants.first.locked = true
    split.apply_even_split

    assert_equal [ 3334, 3333, 3333 ], split.participants.map(&:amount_cents)
    assert_not split.participants.any?(&:locked?)
    assert split.valid?
  end

  test "apply_custom_split keeps the locked rows and respreads the rest" do
    split = build_even_split(total_cents: 10_000, people_count: 3)
    split.split_mode = :custom
    split.participants.first.amount_cents = 5000
    split.participants.first.locked = true
    split.apply_custom_split

    assert_equal [ 5000, 2500, 2500 ], split.participants.map(&:amount_cents)
    assert split.valid?
  end

  # What the screens ask for.

  test "remaining_cents counts amounts the organizer has changed but not saved" do
    split = splits(:dinner)

    assert_equal 0, split.remaining_cents

    split.participants.first.amount_cents = 3000

    assert_equal 334, split.remaining_cents
  end

  test "owed_cents counts only the rows nobody has paid" do
    split = splits(:dinner)

    assert_equal 10_000, split.owed_cents

    split.participants.first.update!(paid_at: Time.current)

    assert_equal 6666, split.reload.owed_cents
  end

  test "a split is fully paid only once every row is paid" do
    split = splits(:dinner)

    assert_not split.fully_paid?

    split.participants.each { |participant| participant.update!(paid_at: Time.current) }

    assert_predicate split.reload, :fully_paid?
  end

  test "participants come back in position order" do
    assert_equal [ 1, 2, 3 ], splits(:dinner).participants.map(&:position)
  end

  test "deleting a split deletes its participants" do
    split = splits(:dinner)

    assert_difference -> { Participant.count }, -3 do
      split.destroy!
    end
  end

  # Scopes the history screen needs.

  test "owned_by finds only that browser's splits" do
    titles = Split.owned_by("organizer-token").pluck(:title)

    assert_includes titles, "Dinner at Rosalia"
    assert_not_includes titles, "Someone else's brunch"
  end

  test "newest_first puts the most recent split at the top" do
    assert_equal "Dinner at Rosalia", Split.owned_by("organizer-token").newest_first.first.title
  end

  private

  # A valid split, built but not saved: a title, a total, and enough rows whose
  # amounts add up. Every test here starts from one and then breaks exactly one
  # thing, so a failure points at a single rule.
  def build_even_split(total_cents: 10_000, people_count: 3, apply_math: true, **attributes)
    split = Split.new({ title: "Dinner", total_cents: total_cents, owner_token: "organizer-token" }
                        .merge(attributes))
    people_count.times { |index| split.participants.build(position: index + 1) }
    split.apply_even_split if apply_math
    split
  end
end
