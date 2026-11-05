class CreatePeople < ActiveRecord::Migration[8.1]
  def change
    create_table :people do |t|
      t.string :name, null: false
      # There are no accounts: a signed cookie holds a random owner_token, and
      # every person belongs to the browser that saved them.
      t.string :owner_token, null: false

      t.timestamps
    end

    # Serves both jobs: enforces "name unique per owner", and is the index the
    # people picker searches, because owner_token is the leading column.
    add_index :people, %i[owner_token name], unique: true
  end
end
