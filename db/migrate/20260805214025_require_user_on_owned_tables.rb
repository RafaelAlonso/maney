class RequireUserOnOwnedTables < ActiveRecord::Migration[8.1]
  TABLES = %i[settings categories cards card_schedules incomes expenses
              installment_purchases budgets].freeze

  def up
    # On a database that already holds a budget, this migration must not be the
    # thing that discovers it: fail by name, pointing at the task that fixes it,
    # instead of dying on a constraint violation halfway through.
    left_behind = TABLES.select { |table| connection.select_value("SELECT 1 FROM #{table} WHERE user_id IS NULL LIMIT 1") }
    if left_behind.any?
      raise ActiveRecord::MigrationError,
            "#{left_behind.join(', ')} ainda têm linhas sem pessoa. Rode `bin/rails users:claim` primeiro " \
            "e só depois retome `bin/rails db:migrate`. NÃO crie uma pessoa por outro caminho (ex.: " \
            "`rails console`) antes disso — se a criar, rode `users:claim` mesmo assim: ele adota essa " \
            "pessoa em vez de recusar, desde que ela ainda não tenha nenhum dado seu."
    end

    TABLES.each { |table| change_column_null table, :user_id, false }

    # The reserved roles are one per person now, not one per database.
    remove_index :categories, :role
    add_index :categories, %i[user_id role], unique: true, where: "role IS NOT NULL"
  end

  def down
    remove_index :categories, %i[user_id role]
    add_index :categories, :role, unique: true, where: "role IS NOT NULL"
    TABLES.each { |table| change_column_null table, :user_id, true }
  end
end
