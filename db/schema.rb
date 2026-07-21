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

ActiveRecord::Schema[8.1].define(version: 2026_07_21_152150) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "card_schedules", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.integer "closing_day", null: false
    t.datetime "created_at", null: false
    t.integer "due_day", null: false
    t.datetime "updated_at", null: false
    t.date "valid_from", null: false
    t.index ["card_id", "valid_from"], name: "index_card_schedules_on_card_id_and_valid_from", unique: true
    t.index ["card_id"], name: "index_card_schedules_on_card_id"
  end

  create_table "cards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "card_schedules", "cards"
end
