class AddUserToOwnedTables < ActiveRecord::Migration[8.1]
  # Child tables (card_schedules, budgets) carry user_id redundantly on purpose:
  # a uniform column is what lets one concern scope every model, and it means an
  # isolation bug cannot hide behind a join.
  TABLES = %i[settings categories cards card_schedules incomes expenses
              installment_purchases budgets].freeze

  # Nullable here. RequireUserOnOwnedTables flips it to NOT NULL once
  # `bin/rails users:claim` has attached the existing rows.
  def change
    TABLES.each { |table| add_reference table, :user, foreign_key: true, null: true }
  end
end
