# A request is now a text to the friend's phone with a link to pay the organizer,
# so the friend's own Venmo/Cash App handles are no longer used. Zelle is gone
# entirely: it has no public link format and no API.
class TextRequestsReplaceFriendHandles < ActiveRecord::Migration[8.1]
  def change
    add_column :people, :phone_number, :string
    remove_column :people, :venmo_handle, :string
    remove_column :people, :cashapp_cashtag, :string
    remove_column :people, :zelle_contact, :string
    remove_column :payment_profiles, :zelle_contact, :string
  end
end
