class AddPaymentHandlesToPeople < ActiveRecord::Migration[8.1]
  def change
    # Where a saved person can be asked for money. Nullable: most people will
    # never have one, and a split works perfectly well without.
    add_column :people, :venmo_handle, :string
    add_column :people, :cashapp_cashtag, :string
    add_column :people, :zelle_contact, :string
  end
end
