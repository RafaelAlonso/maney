class AddStatementLinkToExpenses < ActiveRecord::Migration[8.1]
  def up
    # A statement is derived, never stored; its natural identity is card +
    # nominal closing (+ nominal due), resolved back through
    # Budgeting::CardStatements#find — so that pair is what a payment keeps.
    add_reference :expenses, :statement_card, foreign_key: { to_table: :cards }, null: true
    add_column :expenses, :statement_closing_on, :date
    add_check_constraint :expenses, "(statement_card_id IS NULL) = (statement_closing_on IS NULL)",
                         name: "expenses_statement_link_complete"

    # Existing payments can't be matched to a statement, so status tracking
    # starts at release for everyone already here.
    add_column :settings, :statements_tracked_from, :date
    execute "UPDATE settings SET statements_tracked_from = CURRENT_DATE"
    change_column_null :settings, :statements_tracked_from, false
  end

  def down
    remove_column :settings, :statements_tracked_from
    remove_check_constraint :expenses, name: "expenses_statement_link_complete"
    remove_column :expenses, :statement_closing_on
    remove_reference :expenses, :statement_card
  end
end
