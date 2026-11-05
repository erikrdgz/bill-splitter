require "application_system_test_case"

class CustomSplitsTest < ApplicationSystemTestCase
  test "even mode has no sliders to drag" do
    open_editor_for "90", 3

    assert_no_selector "input[type='range']"
    assert_row_amounts [ "$30.00", "$30.00", "$30.00" ]
  end

  test "switching to custom mode brings out the sliders" do
    open_editor_for "90", 3

    click_on "Custom"

    assert_selector "input[type='range']", count: 3
    assert_button "Spread the rest evenly"
    # Switching mode changes nothing about the money on its own.
    assert_row_amounts [ "$30.00", "$30.00", "$30.00" ]
  end

  # The bug: dropping one person used to re-even everybody else, undoing
  # allocations that had already been made.
  test "setting one share leaves everyone else exactly where they were" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 0

    assert_row_amounts [ "$0.00", "$33.33", "$33.33" ]
    assert_checked_field "Lock Person 1"
    assert_no_checked_field "Lock Person 2"
  end

  test "what you free up shows as left to give" do
    open_custom_editor_for "100", 3

    assert_text "You pay\n$0.00"

    move_slider "Person 1", 0

    assert_text "You pay\n$33.34"
  end

  # The organizer's own worked example: 0 / 33 / 67 out of 100.
  test "the freed share can be handed out by hand" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 0
    move_slider "Person 2", 3300
    move_slider "Person 3", 6700

    assert_row_amounts [ "$0.00", "$33.00", "$67.00" ]
    assert_text "You pay\n$0.00"

    click_on "Save amounts"

    assert_text "Saved."
    assert_row_amounts [ "$0.00", "$33.00", "$67.00" ]
  end

  test "the percentages follow the amounts" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 0
    move_slider "Person 2", 5000

    assert_row_percentages [ "0.0%", "50.0%", "33.3%" ]
  end

  # The reported bug, in the smallest case that shows it: two people at 50/50.
  # Person 2's amount never changed, but its slider's max did, and a range input
  # draws its thumb at value / max — so the thumb slid and the sliders looked
  # chained together.
  test "reducing one share moves nothing about the other slider" do
    open_custom_editor_for "100", 2

    assert_equal "5000", slider_for("Person 2").value
    untouched_max = slider_for("Person 2")[:max]

    move_slider "Person 1", 3000

    assert_row_amounts [ "$30.00", "$50.00" ]
    assert_equal "5000", slider_for("Person 2").value
    # Same value and same range means the thumb cannot have moved a pixel.
    assert_equal untouched_max, slider_for("Person 2")[:max]
    assert_text "You pay\n$20.00"
  end

  test "every slider runs the whole bill, however the others are set" do
    open_custom_editor_for "100", 3

    assert_equal [ "10000", "10000", "10000" ],
                 [ "Person 1", "Person 2", "Person 3" ].map { |name| slider_for(name)[:max] }

    move_slider "Person 1", 0

    assert_equal [ "10000", "10000", "10000" ],
                 [ "Person 1", "Person 2", "Person 3" ].map { |name| slider_for(name)[:max] }
  end

  # The bill is a ceiling. A row can take everything nobody else is holding and
  # not a cent more, so the shares can never come to more than the total.
  test "a share is capped at what the others have not claimed" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 10_000

    assert_row_amounts [ "$33.00", "$33.33", "$33.33" ]

    move_slider "Person 2", 0
    move_slider "Person 1", 10_000

    assert_row_amounts [ "$66.00", "$0.00", "$33.33" ]
    assert_text "You pay\n$0.67"
  end

  # The organizer's own worked example: ask $20 of one person and $30 of another
  # on a $100 bill, and pay the remaining $50 yourself.
  test "a split saves with the organizer covering what nobody was asked for" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 2000
    move_slider "Person 2", 3000
    move_slider "Person 3", 0

    assert_text "You pay\n$50.00"
    assert_button "Save amounts", disabled: false

    click_on "Save amounts"

    assert_text "Saved."
    assert_row_amounts [ "$20.00", "$30.00", "$0.00" ]
    assert_text "You pay\n$50.00"
  end

  test "spread the rest evenly fills in the rows nobody has set" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 0

    assert_text "You pay\n$33.34"

    click_on "Spread the rest evenly"

    # Person 1 was touched, so it is locked and keeps its zero. The two rows
    # nobody has set share the whole bill between them.
    assert_row_amounts [ "$0.00", "$50.00", "$50.00" ]
    assert_text "You pay\n$0.00"
  end

  test "unlocking a row puts it back into the spread" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 4000
    uncheck "Lock Person 1"
    click_on "Spread the rest evenly"

    assert_row_amounts [ "$33.34", "$33.33", "$33.33" ]
  end

  test "the keyboard drives the sliders too" do
    open_custom_editor_for "100", 3

    # Home takes a range input to its minimum, End to its maximum.
    slider_for("Person 1").send_keys(:home)

    assert_row_amounts [ "$0.00", "$33.33", "$33.33" ]
    assert_text "You pay\n$33.34"

    slider_for("Person 2").send_keys(:end)

    # End takes it to everything nobody else is holding.
    assert_row_amounts [ "$0.00", "$66.00", "$33.33" ]
  end

  # The bug: saving from halfway down the page used to throw you back to the top.
  test "saving keeps you where you were on the page" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 0
    move_slider "Person 2", 6667

    scroll_to_bottom
    scrolled_to = page.evaluate_script("window.scrollY")
    assert_operator scrolled_to, :>, 0, "the page should be scrolled before saving"

    click_on "Save amounts"
    assert_text "Saved."

    # Turbo restores the scroll a moment after the morph, so this waits for it
    # the way Capybara's own matchers wait.
    assert_eventually("saving threw the page back to the top") do
      page.evaluate_script("window.scrollY").to_i.positive?
    end
  end

  test "switching back to even frees every row" do
    open_custom_editor_for "100", 3

    move_slider "Person 1", 0
    move_slider "Person 2", 6667
    click_on "Save amounts"
    assert_text "Saved."

    click_on "Even"

    assert_no_selector "input[type='range']"
    assert_row_amounts [ "$33.34", "$33.33", "$33.33" ]
  end

  test "lowering the bill preserves shares, reports the excess, and saves a correction" do
    open_custom_editor_for "100", 2
    enter_bill_amount("10", label: "Total bill")
    click_on "Save name and total"
    assert_text "Over the bill by"
    assert_row_amounts [ "$50.00", "$50.00" ]
    assert_button "$90.00 over the bill", disabled: true

    move_slider "Person 1", 0
    move_slider "Person 2", 1000
    assert_button "Save amounts", disabled: false
    click_on "Save amounts"
    assert_text "Saved."
    assert_field "Total bill", with: "10.00"
    assert_row_amounts [ "$0.00", "$10.00" ]
  end

  private

  def open_editor_for(amount, people_count)
    visit root_path
    enter_bill_amount(amount)
    set_people_count(people_count)
    save_split_and_open_editor
    assert_selector "h1", text: "Edit split"
  end

  def open_custom_editor_for(amount, people_count)
    open_editor_for(amount, people_count)
    click_on "Custom"
    assert_selector "input[type='range']", count: people_count
  end

  def slider_for(name)
    find(%(input[type="range"][aria-label="#{name}'s share"]))
  end

  # Selenium cannot drag a range input usefully, so the value is set and the
  # events a real drag would fire are dispatched. What is being tested is how
  # SplitLogic reacts to those events, which is the part that could break.
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

  def scroll_to_bottom
    execute_script("window.scrollTo(0, document.body.scrollHeight)")
  end
end
