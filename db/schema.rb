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

ActiveRecord::Schema[8.1].define(version: 2026_08_11_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "budgets", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.date "month", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["category_id", "month"], name: "index_budgets_on_category_id_and_month", unique: true
    t.index ["category_id"], name: "index_budgets_on_category_id"
    t.index ["user_id"], name: "index_budgets_on_user_id"
  end

  create_table "card_schedules", force: :cascade do |t|
    t.bigint "card_id", null: false
    t.integer "closing_day", null: false
    t.datetime "created_at", null: false
    t.integer "due_day", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.date "valid_from", null: false
    t.index ["card_id", "valid_from"], name: "index_card_schedules_on_card_id_and_valid_from", unique: true
    t.index ["card_id"], name: "index_card_schedules_on_card_id"
    t.index ["user_id"], name: "index_card_schedules_on_user_id"
  end

  create_table "cards", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_cards_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "role"], name: "index_categories_on_user_id_and_role", unique: true, where: "(role IS NOT NULL)"
    t.index ["user_id"], name: "index_categories_on_user_id"
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
    t.bigint "user_id", null: false
    t.index ["card_id"], name: "index_expenses_on_card_id"
    t.index ["category_id"], name: "index_expenses_on_category_id"
    t.index ["installment_purchase_id"], name: "index_expenses_on_installment_purchase_id"
    t.index ["user_id"], name: "index_expenses_on_user_id"
  end

  create_table "incomes", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_incomes_on_user_id"
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
    t.bigint "user_id", null: false
    t.index ["card_id"], name: "index_installment_purchases_on_card_id"
    t.index ["category_id"], name: "index_installment_purchases_on_category_id"
    t.index ["user_id"], name: "index_installment_purchases_on_user_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.string "delivery_state", default: "sending", null: false
    t.string "email_address", null: false
    t.datetime "expires_at", null: false
    t.bigint "invited_by_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_invitations_on_email_address"
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["token_digest"], name: "index_invitations_on_token_digest", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.integer "alert_threshold_percent", default: 80, null: false
    t.datetime "created_at", null: false
    t.date "first_month", null: false
    t.integer "initial_balance_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_settings_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "access_revoked_at"
    t.boolean "admin", default: false, null: false
    t.string "consent_policy_version"
    t.datetime "consented_at"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "budgets", "categories"
  add_foreign_key "budgets", "users"
  add_foreign_key "card_schedules", "cards"
  add_foreign_key "card_schedules", "users"
  add_foreign_key "cards", "users"
  add_foreign_key "categories", "users"
  add_foreign_key "expenses", "cards"
  add_foreign_key "expenses", "categories"
  add_foreign_key "expenses", "installment_purchases"
  add_foreign_key "expenses", "users"
  add_foreign_key "incomes", "users"
  add_foreign_key "installment_purchases", "cards"
  add_foreign_key "installment_purchases", "categories"
  add_foreign_key "installment_purchases", "users"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "settings", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
