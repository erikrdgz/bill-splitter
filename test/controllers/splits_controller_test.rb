require "test_helper"

class SplitsControllerTest < ActionDispatch::IntegrationTest
  test "the quick split is the front door" do
    get root_url

    assert_response :success
  end

  test "the screen has an amount field, a people stepper, and a save action" do
    get root_url

    assert_select "input[name=?]", "split[amount]"
    assert_select "input[name=?][min=?][max=?]", "split[people_count]", "2", "20"
    assert_select "button[aria-label=?]", "One fewer person"
    assert_select "button[aria-label=?]", "One more person"
    assert_select "input[type=submit][value=?]", "Save and add names"
  end

  test "the screen starts at the minimum number of people" do
    get root_url

    assert_select "input[name=?][value=?]", "split[people_count]", "2"
    assert_select "ol[data-quick-split-logic-target='shares'] > li", 2
  end

  # No amount typed yet, so no figures: the em dash is the empty state.
  test "the share rows start empty because no amount has been entered" do
    get root_url

    assert_select "ol[data-quick-split-logic-target='shares'] > li [data-share-row-amount]" do |amounts|
      assert amounts.all? { |amount| amount.text == "—" }
    end
  end

  test "the rows are named from their position" do
    get root_url

    assert_select "ol[data-quick-split-logic-target='shares'] > li [data-share-row-name]" do |names|
      assert_equal [ "Person 1", "Person 2" ], names.map(&:text)
    end
  end

  # The browser mirrors SplitMath's limits, so they are handed over as Stimulus
  # values rather than written into the JavaScript a second time. If these
  # attributes ever stop matching the constants, the browser and the server
  # would disagree about what is allowed.
  test "the limits reach the browser from SplitMath, not from a hardcoded copy" do
    get root_url

    assert_select "form[data-quick-split-logic-minimum-people-value=?]",
                  SplitMath::PEOPLE_RANGE.min.to_s
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
end
