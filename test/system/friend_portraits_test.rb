require "application_system_test_case"

class FriendPortraitsTest < ApplicationSystemTestCase
  test "sample portraits follow a friend from recents through a saved split" do
    open_sample_contacts
    assert_no_text "Recent friends"
    enter_bill_amount("100")
    start_group
    click_on "Add person", exact: true
    click_on "Connect Person 1"
    assert_selector ".friend-list .avatar-photo", count: 8
    click_on "Choose Maya Chen"
    click_on "Connect", exact: true
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 1
    click_on "Save split"
    assert_selector "#requests .avatar-photo", count: 1
    click_on "Edit split"
    assert_selector "#participants .avatar-photo", count: 1
  end

  test "the next friend peeks in and the fade clears at the end" do
    open_sample_contacts
    start_group
    click_on "Add person", exact: true
    click_on "Connect Person 1"
    assert_selector ".friend-list[data-more-right=true][data-more-left=false]"
    assert page.evaluate_script(<<~JS)
      (() => {
        const strip = document.querySelector('.friend-list').getBoundingClientRect()
        const next = document.querySelector('.friend-list').children[4].getBoundingClientRect()
        return next.left < strip.right && next.right > strip.right
      })()
    JS
    click_on "Choose Alex Rivera"
    click_on "Choose Maya Chen"
    assert_selector ".friend-list[data-more-right=false][data-more-left=true]"
    click_on "Connect", exact: true
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 1
  end

  test "contact search uses the portrait and new contacts retain initials" do
    open_sample_contacts
    start_group
    click_on "Add person", exact: true
    click_on "Connect Person 1"
    fill_in "Name", with: "Maya"
    assert_selector "[role=option] .avatar-photo", count: 1
    find("[role=option]", text: "Maya Chen").click
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 1
    start_group
    click_on "Add person", exact: true
    click_on "Connect Person 2"
    fill_in "Name", with: "Robin Green"
    find("[role=option]", text: "Create contact “Robin Green”").click
    choose "Cash", allow_label_click: true
    click_on "Connect", exact: true
    assert_selector "[data-share-row-avatar]", text: "RG"
    assert_selector "[data-share-row-avatar] .avatar-photo", count: 1
  end

  test "canceling a recent choice keeps the spot and confirmed contacts cannot be duplicated" do
    open_sample_contacts
    enter_bill_amount("3000")
    set_people_count(6)
    click_on "Connect Person 1"
    click_on "Choose Maya Chen"
    click_on "Close connection"
    assert_button "Connect Person 1"
    assert_selector "[data-quick-split-logic-target=countDisplay]", text: "6 people"
    assert_selector "[data-quick-split-logic-target=comparison]", text: /\$500\s+each/
    click_on "Connect Person 1"
    click_on "Choose Maya Chen"
    click_on "Connect", exact: true
    assert_button "Connect Maya Chen"
    assert_selector "[data-quick-split-logic-target=countDisplay]", text: "6 people"
    click_on "Connect Person 2"
    assert_button "Choose Maya Chen", disabled: true
    click_on "Close connection"
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
