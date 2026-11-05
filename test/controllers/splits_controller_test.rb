require "test_helper"

class SplitsControllerTest < ActionDispatch::IntegrationTest
  test "the quick split is the front door" do
    get root_url

    assert_response :success
  end

  test "the screen has an amount field, a people stepper, and a save action" do
    get root_url

    assert_select "input[name=?]", "split[amount]"
    assert_select "input[name=?][type=hidden]", "split[people_count]"
    assert_select "button", text: /Add person/
    assert_select "[data-quick-split-logic-target=countDisplay]", text: "0 people"
    assert_select "input[type=submit][value=?]", "Save split"
  end

  test "the screen starts at the minimum number of people" do
    get root_url

    assert_select "input[name=?][value=?]", "split[people_count]", "0"
    assert_select "ol[data-quick-split-logic-target='shares'] > li", 0
  end

  test "the draft has no placeholder cards before adding people" do
    get root_url
    assert_select "ol[data-quick-split-logic-target=shares] > li", 0
  end

  test "the card template starts with an unnamed first person" do
    get root_url
    assert_select "template [data-share-row-name]", text: "Person 1"
  end

  # The browser mirrors SplitMath's limits, so they are handed over as Stimulus
  # values rather than written into the JavaScript a second time. If these
  # attributes ever stop matching the constants, the browser and the server
  # would disagree about what is allowed.
  test "the limits reach the browser from SplitMath, not from a hardcoded copy" do
    get root_url

    assert_select "form[data-quick-split-logic-minimum-people-value=?]",
                  "0"
    assert_select "form[data-quick-split-logic-maximum-people-value=?]",
                  SplitMath::PEOPLE_RANGE.max.to_s
    assert_select "form[data-quick-split-logic-maximum-total-cents-value=?]",
                  SplitMath::MAXIMUM_TOTAL_CENTS.to_s
  end

  test "the screen saves nothing, because the organizer has not asked it to yet" do
    assert_no_difference [ -> { Split.count }, -> { Participant.count } ] do
      get root_url
    end
  end

  # Saving a quick split.

  test "creating a split from the quick split form redirects to requests" do
    assert_difference -> { Split.count }, 1 do
      post splits_url, params: { split: { amount: "100", people_count: "3" } }
    end

    assert_redirected_to split_path(Split.find(response.location[%r{/splits/(\d+)}, 1]))
  end

  test "the server works the shares out again rather than trusting the browser" do
    split = create_split(amount: "100", people_count: 3)

    assert_equal 10_000, split.total_cents
    assert_equal [ 3334, 3333, 3333 ], split.participants.map(&:amount_cents)
    assert_equal [ 1, 2, 3 ], split.participants.map(&:position)
  end

  test "a new split is named after today until the organizer renames it" do
    assert_equal "Split on #{Date.current.strftime('%B %-d')}", create_split.title
  end

  test "a new split belongs to the browser that made it" do
    split = create_split

    assert split.owner_token.present?
    assert cookies[:owner_token].present?
  end

  test "the rows start out unnamed placeholders" do
    assert_equal [ "Person 1", "Person 2", "Person 3" ],
                 create_split.participants.map(&:display_name)
  end

  test "a split with no amount is refused and nothing is written" do
    assert_no_difference [ -> { Split.count }, -> { Participant.count } ] do
      post splits_url, params: { split: { amount: "", people_count: "3" } }
    end

    assert_response :unprocessable_entity
  end

  test "a split without people is refused" do
    assert_no_difference -> { Split.count } do
      post splits_url, params: { split: { amount: "100", people_count: "0" } }
    end

    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /between 1 and 20 people/
  end

  test "a split can save a single person" do
    split = create_split(amount: "100", people_count: 1)
    assert_equal [ 10000 ], split.participants.map(&:amount_cents)
  end

  # A forged request could ask for a million rows. The controller builds at most
  # one over the maximum, which still fails validation with the right message.
  test "an absurd head count is refused without building a row for each" do
    assert_no_difference -> { Split.count } do
      post splits_url, params: { split: { amount: "100", people_count: "1000000" } }
    end

    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /between 1 and 20 people/
  end

  test "a refused split keeps what the organizer typed" do
    post splits_url, params: { split: { amount: "", people_count: "7" } }

    assert_select "input[name=?][value=?]", "split[people_count]", "7"
  end

  test "connecting recent friends saves the title and assigns owned people once" do
    previous = create_split
    friend = Person.create!(name: "Alex Rivera", owner_token: previous.owner_token)
    post splits_url, params: { split: { amount: "90", title: "Dinner", people_count: "2",
      person_ids: [ friend.id, friend.id ] } }

    split = Split.order(:id).last
    assert_equal "Dinner", split.title
    assert_equal [ friend.id, nil ], split.participants.map(&:person_id)
    assert_equal [ 4500, 4500 ], split.participants.map(&:amount_cents)
  end

  test "recent friends never reveal or accept another browser's people" do
    get root_url
    assert_select "input[value=?][type=checkbox]", people(:marissa).id.to_s, count: 0
    assert_no_difference -> { Split.count } do
      post splits_url, params: { split: { amount: "100", people_count: "2",
        person_ids: [ people(:marissa).id ] } }
    end
    assert_response :not_found
  end

  test "a custom draft preserves shares and records cash without marking it paid" do
    post splits_url, params: { intent: "request", split: { amount: "1000", title: "Dinner", people_count: "2",
      draft_rows: [ { name: "Alex", payment_method: "cash", amount_cents: "20000", locked: "1" },
                    { amount_cents: "20000", locked: "1" } ] } }
    split = Split.order(:id).last
    assert_redirected_to split_path(split)
    assert_equal [ 20000, 20000 ], split.participants.map(&:amount_cents)
    assert_equal 60000, split.remaining_cents
    assert_equal "cash", split.participants.first.payment_method
    assert_nil split.participants.first.paid_at
    assert_equal "Alex", split.participants.first.person.name
  end

  test "an invalid allocation creates neither people nor a split" do
    assert_no_difference [ -> { Split.count }, -> { Person.count } ] do
      post splits_url, params: { split: { amount: "100", people_count: "2",
        draft_rows: [ { name: "New friend", payment_method: "cash", amount_cents: "9000", locked: "1" },
                      { amount_cents: "9000", locked: "1" } ] } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /cannot come to more than the total/
  end

  test "a draft refuses foreign people and unknown payment methods" do
    assert_no_difference -> { Split.count } do
      post splits_url, params: { split: { amount: "100", people_count: "2",
        draft_rows: [ { person_id: people(:marissa).id, amount_cents: "5000" }, { amount_cents: "5000" } ] } }
    end
    assert_response :not_found
    assert_no_difference [ -> { Split.count }, -> { Person.count } ] do
      post splits_url, params: { split: { amount: "100", people_count: "2",
        draft_rows: [ { name: "Alex", payment_method: "unknown", amount_cents: "5000" }, { amount_cents: "5000" } ] } }
    end
    assert_response :unprocessable_entity
  end

  test "an invalid phone number rolls back the entire draft" do
    assert_no_difference [ -> { Split.count }, -> { Person.count } ] do
      post splits_url, params: { split: { amount: "100", people_count: "2",
        draft_rows: [ { name: "Alex", payment_method: "venmo", phone_number: "not a number", amount_cents: "5000" },
                      { amount_cents: "5000" } ] } }
    end
    assert_response :unprocessable_entity
  end

  # Editing.

  test "the editor shows the split and its rows" do
    split = create_split(amount: "100", people_count: 3)

    get edit_split_url(split)

    assert_response :success
    assert_select "input[name=?][value=?]", "split[title]", split.title
    assert_select "input[name=?][value=?]", "split[amount]", "100.00"
    assert_select "ol#participants > li", 3
    assert_select "#remaining", text: /\$0\.00/
  end

  test "the editor shows each row's share and percentage" do
    split = create_split(amount: "100", people_count: 3)

    get edit_split_url(split)

    assert_select "##{ActionView::RecordIdentifier.dom_id(split.participants.first)}",
                  text: /Person 1.*33\.3%.*\$33\.34/m
  end

  # The spec's ownership test.

  test "a browser with a different owner cookie cannot edit someone else's split" do
    get edit_split_url(splits(:stranger_brunch))

    assert_response :not_found
  end

  test "a browser with a different owner cookie cannot update someone else's split" do
    patch split_url(splits(:stranger_brunch)), params: { split: { title: "Mine now" } }

    assert_response :not_found
    assert_equal "Someone else's brunch", splits(:stranger_brunch).reload.title
  end

  test "renaming a split keeps its amounts" do
    split = create_split(amount: "100", people_count: 3)

    patch split_url(split), params: { split: { title: "Dinner at Rosalia" } }

    assert_redirected_to edit_split_path(split)
    assert_equal "Dinner at Rosalia", split.reload.title
    assert_equal [ 3334, 3333, 3333 ], split.participants.map(&:amount_cents)
  end

  test "changing the total respreads the shares so they still add up" do
    split = create_split(amount: "100", people_count: 3)

    patch split_url(split), params: { split: { amount: "90" } }

    split.reload

    assert_equal 9000, split.total_cents
    assert_equal [ 3000, 3000, 3000 ], split.participants.map(&:amount_cents)
    assert_equal 0, split.remaining_cents
  end

  test "a total that would leave somebody nothing is refused" do
    split = create_split(amount: "100", people_count: 3)

    patch split_url(split), params: { split: { amount: "0.02" } }

    assert_response :unprocessable_entity
    assert_equal 10_000, split.reload.total_cents
  end

  test "a total above the maximum is refused" do
    split = create_split(amount: "100", people_count: 3)

    patch split_url(split), params: { split: { amount: "100000" } }

    assert_response :unprocessable_entity
    assert_equal 10_000, split.reload.total_cents
  end

  # History.

  test "history invites starting a split when there is nothing in it" do
    get splits_url

    assert_response :success
    assert_select "#splits", false
    assert_select "a[href=?]", root_path, text: "Split a bill"
  end

  test "history lists this browser's splits newest first" do
    older = create_split(amount: "45", people_count: 2)
    older.update!(title: "Taxi home", created_at: 3.days.ago)
    newer = create_split(amount: "100", people_count: 3)
    newer.update!(title: "Dinner")

    get splits_url

    assert_select "#splits > li", 2
    assert_select "#splits > li:first-child", text: /Dinner/
    assert_select "#splits > li:last-child", text: /Taxi home/
  end

  test "each split shows its total and what is still owed" do
    split = create_split(amount: "100", people_count: 3)
    split.participants.first.update!(paid_at: Time.current)

    get splits_url

    assert_select "#splits > li", text: /\$100\.00.*\$66\.66 owed/m
  end

  test "a fully paid split says so rather than showing nothing owed" do
    split = create_split(amount: "100", people_count: 2)
    split.participants.each { |participant| participant.update!(paid_at: Time.current) }

    get splits_url

    assert_select "#splits > li", text: /All paid/
  end

  test "history shows only this browser's splits" do
    create_split(amount: "100", people_count: 3)

    get splits_url

    assert_select "#splits > li", 1
    assert_select "#splits", text: /Someone else's brunch/, count: 0
  end

  test "tapping a split opens its detail page" do
    split = create_split(amount: "100", people_count: 3)

    get splits_url

    assert_select "#splits > li a[href=?]", split_path(split)
  end

  # Every row adds up its own participants. Without includes(:participants) that
  # is a query per split, so the page would get slower the more it has to show.
  test "history does not run a query per split" do
    3.times { create_split(amount: "100", people_count: 3) }
    queries_for_three = count_queries { get splits_url }

    3.times { create_split(amount: "100", people_count: 3) }
    queries_for_six = count_queries { get splits_url }

    assert_equal queries_for_three, queries_for_six,
                 "the number of queries grew with the number of splits"
  end

  # The organizer's own view of a split.

  test "the detail page shows who has paid and what is still owed" do
    split = create_split(amount: "100", people_count: 3)
    split.participants.first.update!(paid_at: Time.current)

    get split_url(split)

    assert_response :success
    assert_select "ol#participants > li", 1
    assert_select "ol#requests > li", 2
    assert_select ".request-balance", text: /\$66\.66/
  end

  # Marking somebody paid is something they do on their own share link.
  test "the detail page reports rather than offering to mark people paid" do
    split = create_split(amount: "100", people_count: 3)

    get split_url(split)

    assert_select "button", text: "I paid", count: 0
    assert_select "ol#requests > li", count: 3
  end

  test "the detail page offers the share link to copy" do
    split = create_split(amount: "100", people_count: 3)

    get split_url(split)

    assert_select "input[readonly][value=?]", share_url(split.share_token)
    assert_select "[data-controller=copy-logic]"
  end

  test "a browser with a different owner cookie cannot see someone else's detail page" do
    get split_url(splits(:stranger_brunch))

    assert_response :not_found
  end

  # Custom mode.

  test "a split starts in even mode and can be switched to custom" do
    split = create_split(amount: "100", people_count: 3)

    assert_predicate split, :even?

    patch split_url(split), params: { split: { split_mode: "custom" } }

    assert_predicate split.reload, :custom?
  end

  test "custom amounts are respread around the locked rows" do
    split = create_split(amount: "100", people_count: 3)
    patch split_url(split), params: { split: { split_mode: "custom" } }
    first, second, third = split.reload.participants.to_a

    patch split_url(split), params: { split: {
      participants_attributes: [
        { id: first.id, amount_cents: 5000, locked: "1" },
        { id: second.id, amount_cents: 2500, locked: "0" },
        { id: third.id, amount_cents: 2500, locked: "0" }
      ]
    } }

    assert_equal [ 5000, 2500, 2500 ], split.reload.participants.map(&:amount_cents)
    assert_equal [ true, false, false ], split.participants.map(&:locked?)
  end

  # Custom mode is hand allocation, so the server takes the posted amounts as
  # the organizer's decision rather than rewriting them. What it will not do is
  # store a split that does not add up.
  test "custom amounts that come to more than the bill are refused" do
    split = create_split(amount: "100", people_count: 3)
    patch split_url(split), params: { split: { split_mode: "custom" } }
    first, second, third = split.reload.participants.to_a

    patch split_url(split), params: { split: {
      participants_attributes: [
        { id: first.id, amount_cents: 6000, locked: "1" },
        { id: second.id, amount_cents: 9999, locked: "0" },
        { id: third.id, amount_cents: 9999, locked: "0" }
      ]
    } }

    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /cannot come to more than the total/
    assert_equal [ 3334, 3333, 3333 ], split.reload.participants.map(&:amount_cents)
  end

  # The bug this replaced: dropping one row used to re-even every other row,
  # undoing allocations the organizer had already made.
  test "setting one row leaves the others exactly where they were" do
    split = create_split(amount: "100", people_count: 3)
    patch split_url(split), params: { split: { split_mode: "custom" } }
    first, second, third = split.reload.participants.to_a

    # Start from 20 / 30 / 50.
    patch split_url(split), params: { split: {
      participants_attributes: [
        { id: first.id, amount_cents: 2000, locked: "1" },
        { id: second.id, amount_cents: 3000, locked: "1" },
        { id: third.id, amount_cents: 5000, locked: "1" }
      ]
    } }

    assert_equal [ 2000, 3000, 5000 ], split.reload.participants.map(&:amount_cents)

    # Drop the first to zero and hand its share to the other two by hand.
    patch split_url(split), params: { split: {
      participants_attributes: [
        { id: first.id, amount_cents: 0, locked: "1" },
        { id: second.id, amount_cents: 3300, locked: "1" },
        { id: third.id, amount_cents: 6700, locked: "1" }
      ]
    } }

    assert_equal [ 0, 3300, 6700 ], split.reload.participants.map(&:amount_cents)
  end

  test "locked rows that come to more than the total are refused" do
    split = create_split(amount: "100", people_count: 3)
    patch split_url(split), params: { split: { split_mode: "custom" } }
    first, second, third = split.reload.participants.to_a

    patch split_url(split), params: { split: {
      participants_attributes: [
        { id: first.id, amount_cents: 9000, locked: "1" },
        { id: second.id, amount_cents: 9000, locked: "1" },
        { id: third.id, amount_cents: 0, locked: "0" }
      ]
    } }

    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /cannot come to more than the total/
    assert_equal [ 3334, 3333, 3333 ], split.reload.participants.map(&:amount_cents)
  end

  test "switching back to even frees every row and spreads the money again" do
    split = create_split(amount: "100", people_count: 3)
    patch split_url(split), params: { split: { split_mode: "custom" } }
    first, second, third = split.reload.participants.to_a

    patch split_url(split), params: { split: {
      participants_attributes: [
        { id: first.id, amount_cents: 5000, locked: "1" },
        { id: second.id, amount_cents: 2500, locked: "0" },
        { id: third.id, amount_cents: 2500, locked: "0" }
      ]
    } }

    assert_predicate split.reload.participants.first, :locked?

    patch split_url(split), params: { split: { split_mode: "even" } }

    split.reload

    assert_equal [ 3334, 3333, 3333 ], split.participants.map(&:amount_cents)
    assert_not split.participants.any?(&:locked?)
  end

  test "a row from another split cannot be smuggled into the nested attributes" do
    split = create_split(amount: "100", people_count: 3)

    patch split_url(split), params: { split: {
      participants_attributes: [
        { id: participants(:stranger_one).id, amount_cents: 1, locked: "1" }
      ]
    } }

    assert_response :not_found
    assert_equal 3000, participants(:stranger_one).reload.amount_cents
  end

  test "a split can never be saved in a state that does not add up" do
    split = create_split(amount: "100", people_count: 3)

    patch split_url(split), params: { split: { amount: "77.77" } }

    split.reload

    assert_equal 7777, split.total_cents
    assert_equal 7777, split.participants.sum(&:amount_cents)
  end
end
