class CreateParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :participants do |t|
      # index: false because the unique index below already leads with split_id.
      t.references :split, null: false, foreign_key: true, index: false
      # Optional: a participant with no person is a placeholder shown as "Person 3".
      t.references :person, null: true, foreign_key: true
      # position sets list order and who gets the leftover cent. 1-based.
      t.integer :position, null: false
      t.integer :amount_cents, null: false, default: 0
      # locked means the organizer set this amount by hand, so the math leaves it alone.
      t.boolean :locked, null: false, default: false
      # Empty until a friend taps "I paid" on the share page.
      t.datetime :paid_at

      t.timestamps
    end

    add_index :participants, %i[split_id position], unique: true

    add_check_constraint :participants, "amount_cents >= 0",
                         name: "participants_amount_cents_not_negative"
    add_check_constraint :participants, "position > 0",
                         name: "participants_position_positive"
  end
end
