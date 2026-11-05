# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_05_044147) do
  create_table "participants", force: :cascade do |t|
    t.integer "split_id", null: false
    t.integer "person_id"
    t.integer "position", null: false
    t.integer "amount_cents", default: 0, null: false
    t.boolean "locked", default: false, null: false
    t.datetime "paid_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["person_id"], name: "index_participants_on_person_id"
    t.index ["split_id", "position"], name: "index_participants_on_split_id_and_position", unique: true
    t.check_constraint "amount_cents >= 0", name: "participants_amount_cents_not_negative"
    t.check_constraint "position > 0", name: "participants_position_positive"
  end

  create_table "people", force: :cascade do |t|
    t.string "name", null: false
    t.string "owner_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_token", "name"], name: "index_people_on_owner_token_and_name", unique: true
  end

  create_table "splits", force: :cascade do |t|
    t.string "title", null: false
    t.integer "total_cents", null: false
    t.string "split_mode", default: "even", null: false
    t.string "share_token", null: false
    t.string "owner_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_token", "created_at"], name: "index_splits_on_owner_token_and_created_at"
    t.index ["share_token"], name: "index_splits_on_share_token", unique: true
    t.check_constraint "split_mode IN ('even', 'custom')", name: "splits_split_mode_known"
    t.check_constraint "total_cents > 0 AND total_cents <= 9999999", name: "splits_total_cents_within_limits"
  end

  add_foreign_key "participants", "people"
  add_foreign_key "participants", "splits"
end
