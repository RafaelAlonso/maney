class AddAccountToExpensesAndIncomes < ActiveRecord::Migration[8.1]
  def up
    add_reference :expenses, :account, foreign_key: true, null: true
    add_reference :incomes, :account, foreign_key: true, null: true

    self.class.backfill(connection)

    change_column_null :incomes, :account_id, false
    # Crédito never touches an account (it moves when the bill is paid);
    # débito and dinheiro always do.
    add_check_constraint :expenses, "(payment_method = 'credit') = (account_id IS NULL)",
                         name: "expenses_account_matches_method"
  end

  def down
    remove_check_constraint :expenses, name: "expenses_account_matches_method"
    remove_reference :incomes, :account
    remove_reference :expenses, :account
  end

  # All existing history moves into each person's Conta principal — dinheiro
  # too: past cash had no saque recorded, so putting it in the carteira would
  # leave the carteira deeply negative. Raw SQL so no default scope applies.
  def self.backfill(connection)
    connection.execute(<<~SQL)
      UPDATE expenses SET account_id = accounts.id
      FROM accounts
      WHERE accounts.user_id = expenses.user_id AND accounts.role = 'primary'
        AND expenses.payment_method IN ('debit', 'cash') AND expenses.account_id IS NULL
    SQL
    connection.execute(<<~SQL)
      UPDATE incomes SET account_id = accounts.id
      FROM accounts
      WHERE accounts.user_id = incomes.user_id AND accounts.role = 'primary'
        AND incomes.account_id IS NULL
    SQL
  end
end
