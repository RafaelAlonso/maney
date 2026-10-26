require "rails_helper"
require Rails.root.join("db/migrate/20261026000002_add_account_to_expenses_and_incomes")

# The backfill runs once, against rows that predate accounts. The test database
# is fully migrated, so the pre-migration state is rebuilt inside the example's
# transaction (PostgreSQL DDL is transactional, so the ROLLBACK undoes it).
RSpec.describe AddAccountToExpensesAndIncomes do
  let(:connection) { ActiveRecord::Base.connection }

  before do
    create_setting!
    connection.execute("ALTER TABLE expenses DROP CONSTRAINT expenses_account_matches_method")
    connection.change_column_null(:incomes, :account_id, true)
  end

  def insert(sql) = connection.select_value("#{sql} RETURNING id")

  it "moves every débito and dinheiro expense and every income into the primary account, and leaves crédito alone" do
    card = create_card!
    mercado = category("mercado")
    other = create_user!(email_address: "irma@example.com")
    other_primary = as(other) { create_setting!; Account.primary }

    uid = current_user.id
    debit = insert("INSERT INTO expenses (user_id, name, amount_cents, date, payment_method, category_id, created_at, updated_at) " \
                   "VALUES (#{uid}, 'feira', 100, '2026-03-05', 'debit', #{mercado.id}, NOW(), NOW())")
    cash = insert("INSERT INTO expenses (user_id, name, amount_cents, date, payment_method, category_id, created_at, updated_at) " \
                  "VALUES (#{uid}, 'pão', 100, '2026-03-05', 'cash', #{mercado.id}, NOW(), NOW())")
    credit = insert("INSERT INTO expenses (user_id, name, amount_cents, date, payment_method, category_id, card_id, created_at, updated_at) " \
                    "VALUES (#{uid}, 'tv', 100, '2026-03-05', 'credit', #{mercado.id}, #{card.id}, NOW(), NOW())")
    income = insert("INSERT INTO incomes (user_id, name, amount_cents, date, created_at, updated_at) " \
                    "VALUES (#{uid}, 'salário', 100, '2026-03-05', NOW(), NOW())")
    other_income = insert("INSERT INTO incomes (user_id, name, amount_cents, date, created_at, updated_at) " \
                          "VALUES (#{other.id}, 'salário', 100, '2026-03-05', NOW(), NOW())")

    described_class.backfill(connection)

    primary = Account.primary
    expect(Expense.find(debit).account).to eq(primary)
    expect(Expense.find(cash).account).to eq(primary)
    expect(Expense.find(credit).account).to be_nil
    expect(Income.find(income).account).to eq(primary)
    expect(Income.unscoped.find(other_income).account_id).to eq(other_primary.id)
  end
end
