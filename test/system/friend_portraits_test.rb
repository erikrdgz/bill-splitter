require "application_system_test_case"

class FriendPortraitsTest < ApplicationSystemTestCase
  test "sample portraits follow a friend from recents through a saved split" do
    open_sample_contacts
    assert_selector ".friend-list .avatar-photo", count: 8
    enter_bill_amount("100")
    click_on "Add Maya Chen"
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 1
    click_on "Save split"
    assert_selector "#requests .avatar-photo", count: 1
    click_on "Edit split"
    assert_selector "#participants .avatar-photo", count: 1
  end

  test "the next friend peeks in and the fade clears at the end" do
    open_sample_contacts
    assert_selector ".friend-list[data-more-right=true][data-more-left=false]"
    assert page.evaluate_script(<<~JS)
      (() => {
        const strip = document.querySelector('.friend-list').getBoundingClientRect()
        const next = document.querySelector('.friend-list').children[4].getBoundingClientRect()
        return next.left < strip.right && next.right > strip.right
      })()
    JS
    click_on "Add Alex Rivera"
    click_on "Add Maya Chen"
    assert_selector ".friend-list[data-more-right=false][data-more-left=true]"
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 2
  end

  test "contact search uses the portrait and new contacts retain initials" do
    open_sample_contacts
    click_on "Add", exact: true
    click_on "Connect Person 1"
    fill_in "Name", with: "Maya"
    assert_selector "[role=option] .avatar-photo", count: 1
    find("[role=option]", text: "Maya Chen").click
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 1
    click_on "Add", exact: true
    click_on "Connect Person 2"
    fill_in "Name", with: "Robin Green"
    find("[role=option]", text: "Create contact “Robin Green”").click
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true
    assert_selector "[data-share-row-avatar]", text: "RG"
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 1
  end

  private

  def open_sample_contacts
    visit root_path
    enter_bill_amount("100")
    set_people_count(1)
    save_split_and_open_editor
    split = Split.find(current_url[%r{/splits/(\d+)}, 1])
    DevelopmentContacts.populate(split.owner_token)
    visit root_path
  end
end
