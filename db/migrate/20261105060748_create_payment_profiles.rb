class CreatePaymentProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :payment_profiles do |t|
      # One profile per browser, same as everything else here: no accounts, just
      # the signed cookie. This is where the organizer keeps the handles friends
      # pay them at.
      t.string :owner_token, null: false
      t.string :venmo_handle
      t.string :cashapp_cashtag
      t.string :zelle_contact

      t.timestamps
    end

    add_index :payment_profiles, :owner_token, unique: true
  end
end
