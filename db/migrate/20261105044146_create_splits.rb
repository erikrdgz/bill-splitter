class CreateSplits < ActiveRecord::Migration[8.1]
  def change
    create_table :splits do |t|
      t.string :title, null: false
      # Money is whole cents, never a float. See SplitMath.
      t.integer :total_cents, null: false
      t.string :split_mode, null: false, default: "even"
      # has_secure_token fills this in before insert, so the link is hard to guess.
      t.string :share_token, null: false
      t.string :owner_token, null: false

      t.timestamps
    end

    add_index :splits, :share_token, unique: true
    # History asks for one owner's splits, newest first, so index both columns
    # in that order and the database can answer without sorting.
    add_index :splits, %i[owner_token created_at]

    # The model validates all of this too. These constraints are the backstop:
    # a bug that skips validations still cannot write impossible money.
    add_check_constraint :splits, "total_cents > 0 AND total_cents <= 9999999",
                         name: "splits_total_cents_within_limits"
    add_check_constraint :splits, "split_mode IN ('even', 'custom')",
                         name: "splits_split_mode_known"
  end
end
