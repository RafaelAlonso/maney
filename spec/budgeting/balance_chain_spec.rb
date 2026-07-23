require "rails_helper"

RSpec.describe Budgeting::BalanceChain do
  it "AC 17: the given initial balance enters as the first month's carried balance" do
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 200_000)
    expect(described_class.carried_into(month: Date.new(2026, 3, 1))).to eq(200_000)
  end

  it "AC 16: March closed with current balance 2.800 → April carries 2.800; closed at −300 → April carries −300" do
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))
    Expense.create!(name: "gastos", amount_cents: 220_000, date: Date.new(2026, 3, 10),
                    payment_method: "debit", category: Category.create!(name: "geral"))
    expect(described_class.carried_into(month: Date.new(2026, 4, 1))).to eq(280_000)

    Expense.create!(name: "extra", amount_cents: 310_000, date: Date.new(2026, 3, 20),
                    payment_method: "cash", category: Category.find_by!(name: "geral"))
    expect(described_class.carried_into(month: Date.new(2026, 4, 1))).to eq(-30_000)
  end

  it "edge: a negative balance propagates through several empty months" do
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: -30_000)
    expect(described_class.carried_into(month: Date.new(2026, 6, 1))).to eq(-30_000)
  end

  it "with no setting or before the first month, the carried balance is zero" do
    expect(described_class.carried_into(month: Date.new(2026, 3, 1))).to eq(0)
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 100)
    expect(described_class.carried_into(month: Date.new(2026, 2, 1))).to eq(0)
  end
end
