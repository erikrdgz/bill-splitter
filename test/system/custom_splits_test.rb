require "application_system_test_case"

# Custom shares are set on the people step of the composer: drag a slider, type
# a percentage, or open the keypad on an amount. Setting a row locks it by
# hand; "Split evenly" gives every row back to the spread. These tests drive the
# unsaved draft, and one of them saves it to prove the amounts survive.
class CustomSplitsTest < ApplicationSystemTestCase
  test "a fresh split is even, with a slider on every row" do
    open_composer_for "90", 3

    assert_selector "input[type='range']", count: 3
    assert_equal [ "$30", "$30", "$30" ], share_amounts
  end

  # The bug: dropping one person used to re-even everybody else, undoing
  # allocations that had already been made.
  test "setting one share leaves everyone else exactly where they were" do
    open_composer_for "100", 3

    move_slider "Person 1", 0

    assert_equal [ "$0", "$33.33", "$33.33" ], share_amounts
    assert_selector "input[data-draft-field=locked][value='1']", visible: :all, count: 1
  end

  test "what you free up shows as left to give" do
    open_composer_for "100", 3

    assert_text "You pay\n$0"

    move_slider "Person 1", 0

    assert_text "You pay\n$33.34"
  end

  # The organizer's own worked example: 0 / 33 / 67 out of 100.
  test "the freed share can be handed out by hand and survives saving" do
    open_composer_for "100", 3

    move_slider "Person 1", 0
    move_slider "Person 2", 3300
    move_slider "Person 3", 6700

    assert_equal [ "$0", "$33", "$67" ], share_amounts
    assert_text "You pay\n$0"

    save_split_and_open_editor

    assert_equal [ "$0", "$33", "$67" ], share_amounts
  end

  test "the percentages follow the amounts" do
    open_composer_for "100", 3

    move_slider "Person 1", 0
    move_slider "Person 2", 5000

    assert_field "Person 1's percentage", with: "0"
    assert_field "Person 2's percentage", with: "50"
    assert_field "Person 3's percentage", with: "33.3"
  end

  test "typing a percentage sets that share of the bill" do
    open_composer_for "200", 2

    fill_in "Person 1's percentage", with: "25"
    find_field("Person 1's percentage").send_keys(:tab)

    assert_equal [ "$50", "$100" ], share_amounts
    assert_text "You pay\n$50"
  end

  # The reported bug, in the smallest case that shows it: two people at 50/50.
  # Person 2's amount never changed, but its slider's max did, and a range input
  # draws its thumb at value / max — so the thumb slid and the sliders looked
  # chained together.
  test "reducing one share moves nothing about the other slider" do
    open_composer_for "100", 2

    assert_equal "5000", slider_for("Person 2").value
    untouched_max = slider_for("Person 2")[:max]

    move_slider "Person 1", 3000

    assert_equal [ "$30", "$50" ], share_amounts
    assert_equal "5000", slider_for("Person 2").value
    # Same value and same range means the thumb cannot have moved a pixel.
    assert_equal untouched_max, slider_for("Person 2")[:max]
    assert_text "You pay\n$20"
  end

  test "every slider runs the whole bill, however the others are set" do
    open_composer_for "100", 3

    assert_equal [ "10000", "10000", "10000" ],
                 [ "Person 1", "Person 2", "Person 3" ].map { |name| slider_for(name)[:max] }

    move_slider "Person 1", 0

    assert_equal [ "10000", "10000", "10000" ],
                 [ "Person 1", "Person 2", "Person 3" ].map { |name| slider_for(name)[:max] }
  end

  # The bill is a ceiling. A row can take everything nobody else is holding and
  # not a cent more, so the shares can never come to more than the total. A
  # drag moves in whole dollars, so what is left over is rounded down.
  test "a share is capped at what the others have not claimed" do
    open_composer_for "100", 3

    move_slider "Person 1", 10_000

    assert_equal [ "$33", "$33.33", "$33.33" ], share_amounts

    move_slider "Person 2", 0
    move_slider "Person 1", 10_000

    assert_equal [ "$66", "$0", "$33.33" ], share_amounts
    assert_text "You pay\n$0.67"
  end

  # The organizer's own worked example: ask $20 of one person and $30 of another
  # on a $100 bill, and pay the remaining $50 yourself.
  test "a split saves with the organizer covering what nobody was asked for" do
    open_composer_for "100", 3

    move_slider "Person 1", 2000
    move_slider "Person 2", 3000
    move_slider "Person 3", 0

    assert_text "You pay\n$50"

    save_split

    assert_selector "#requests .request-amount", text: "$20.00"
    assert_selector "#requests .request-amount", text: "$30.00"
    assert_selector ".request-balance", text: /You pay\s+\$50\.00/
  end

  test "the keyboard drives the sliders too" do
    open_composer_for "100", 3

    # Home takes a range input to its minimum, End to its maximum.
    slider_for("Person 1").send_keys(:home)

    assert_equal [ "$0", "$33.33", "$33.33" ], share_amounts
    assert_text "You pay\n$33.34"

    slider_for("Person 2").send_keys(:end)

    # End takes it to everything nobody else is holding.
    assert_equal [ "$0", "$66", "$33.33" ], share_amounts
  end

  test "splitting evenly frees every row and spreads the bill again" do
    open_composer_for "100", 3

    move_slider "Person 1", 0
    move_slider "Person 2", 6600
    assert_selector "input[data-draft-field=locked][value='1']", visible: :all, count: 2

    click_on "Split evenly"

    assert_equal [ "$33.34", "$33.33", "$33.33" ], share_amounts
    assert_selector "input[data-draft-field=locked][value='1']", visible: :all, count: 0
  end

  test "lowering the bill preserves shares, reports the excess, and saves a correction" do
    open_composer_for "100", 2
    move_slider "Person 1", 5000
    edit_bill_details(amount: "10")

    assert_text "Over the bill by\n$90"
    assert_equal [ "$50", "$50" ], share_amounts
    assert_button "Next", disabled: true

    move_slider "Person 1", 0
    move_slider "Person 2", 1000
    assert_text "You pay\n$0"
    save_split

    assert_selector ".request-context", text: "$10.00 total"
    assert_selector "#requests .request-amount", text: "$10.00"
  end

  private

  # No need to save first: the sliders belong to the unsaved draft.
  def open_composer_for(amount, people_count)
    visit root_path
    enter_bill_amount(amount)
    set_people_count(people_count)
  end

  def slider_for(name)
    find(%(input[type="range"][aria-label="#{name}'s share"]))
  end

  # Selenium cannot drag a range input usefully, so the value is set and the
  # events a real drag would fire are dispatched. What is being tested is how
  # QuickSplitLogic reacts to those events, which is the part that could break.
  #
  # A range input clamps whatever it is given to its own max, which is exactly
  # how rule 4 is enforced in the browser — so asking for more than is available
  # here behaves the same as dragging past the end of the track.
  def move_slider(name, cents)
    execute_script(<<~JS, slider_for(name), cents)
      const [ slider, value ] = arguments
      slider.value = value
      slider.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end
end
