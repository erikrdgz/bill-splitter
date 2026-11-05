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
    assert_text "Rows you touch lock"
    # Switching mode changes nothing about the money on its own.
    assert_row_amounts [ "$30.00", "$30.00", "$30.00" ]
  end

  # The point of the whole controller: the untouched rows move while the slider
  # is still being dragged, before anything is saved.
  test "dragging a share locks that row and moves the untouched rows live" do
    open_custom_editor_for "90", 3

    move_slider "Person 1", 6000

    assert_row_amounts [ "$60.00", "$15.00", "$15.00" ]
    assert_checked_field "Lock Person 1"
    assert_no_checked_field "Lock Person 2"
    assert_text "Remaining\n$0.00"
  end

  test "the percentages follow the amounts" do
    open_custom_editor_for "90", 3

    move_slider "Person 1", 4500

    assert_row_percentages [ "50.0%", "25.0%", "25.0%" ]
  end

  test "letting go saves, and the server's amounts are what stick" do
    open_custom_editor_for "90", 3

    move_slider "Person 1", 6000
    release_slider "Person 1"

    assert_text "Saved."
    assert_row_amounts [ "$60.00", "$15.00", "$15.00" ]
    assert_checked_field "Lock Person 1"
  end

  test "the keyboard drives the sliders too" do
    open_custom_editor_for "90", 3

    # End takes a range input to its maximum, which here is the whole total.
    slider_for("Person 1").send_keys(:end)

    assert_text "Saved."
    assert_row_amounts [ "$90.00", "$0.00", "$0.00" ]
  end

  test "a locked row keeps its share while the others are dragged" do
    open_custom_editor_for "120", 3

    move_slider "Person 1", 6000
    move_slider "Person 2", 4000

    assert_row_amounts [ "$60.00", "$40.00", "$20.00" ]
  end

  # Rule 4: with one row left unlocked, its amount is whatever is left, so there
  # is nothing to drag.
  test "the last unlocked slider is disabled" do
    open_custom_editor_for "90", 3

    check "Lock Person 1"
    check "Lock Person 2"

    assert slider_for("Person 3").disabled?
    assert_not slider_for("Person 1").disabled?
  end

  test "unlocking a row puts it back in the pool" do
    open_custom_editor_for "90", 3

    move_slider "Person 1", 6000

    assert_row_amounts [ "$60.00", "$15.00", "$15.00" ]

    uncheck "Lock Person 1"

    assert_row_amounts [ "$30.00", "$30.00", "$30.00" ]
  end

  test "switching back to even frees every row" do
    open_custom_editor_for "90", 3

    move_slider "Person 1", 6000
    release_slider "Person 1"
    assert_text "Saved."

    click_on "Even"

    # Wait for the reloaded page before reading the rows: all() does not retry.
    assert_no_selector "input[type='range']"

    assert_row_amounts [ "$30.00", "$30.00", "$30.00" ]
  end

  private

  def open_editor_for(amount, people_count)
    visit root_path
    fill_in "Amount", with: amount
    fill_in "People", with: people_count
    click_on "Save and add names"
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
  def move_slider(name, cents)
    execute_script(<<~JS, slider_for(name), cents)
      const [ slider, value ] = arguments
      slider.value = value
      slider.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end

  def release_slider(name)
    execute_script(<<~JS, slider_for(name))
      arguments[0].dispatchEvent(new Event("change", { bubbles: true }))
    JS
  end
end
