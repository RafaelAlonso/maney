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

ActiveRecord::Schema[8.1].define(version: 2026_07_21_154744) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "budgets", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.date "month", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "month"], name: "index_budgets_on_category_id_and_month", unique: true
    t.index ["category_id"], name: "index_budgets_on_category_id"
  end

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

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["role"], name: "index_categories_on_role", unique: true, where: "(role IS NOT NULL)"
  end

  create_table "expenses", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "card_id"
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.date "date"
    t.integer "installment_number"
    t.bigint "installment_purchase_id"
    t.string "name", null: false
    t.string "payment_method", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_expenses_on_card_id"
    t.index ["category_id"], name: "index_expenses_on_category_id"
    t.index ["installment_purchase_id"], name: "index_expenses_on_installment_purchase_id"
  end

  create_table "incomes", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "installment_purchases", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "first_installment", default: 1, null: false
    t.integer "installments_count", null: false
    t.string "name", null: false
    t.integer "total_cents", null: false
    t.datetime "updated_at", null: false
    t.index ["card_id"], name: "index_installment_purchases_on_card_id"
    t.index ["category_id"], name: "index_installment_purchases_on_category_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "first_month", null: false
    t.integer "initial_balance_cents", default: 0, null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "budgets", "categories"
  add_foreign_key "card_schedules", "cards"
  add_foreign_key "expenses", "cards"
  add_foreign_key "expenses", "categories"
  add_foreign_key "expenses", "installment_purchases"
  add_foreign_key "installment_purchases", "cards"
  add_foreign_key "installment_purchases", "categories"
end
