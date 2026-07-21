require "rails_helper"

RSpec.describe Budgeting::BalanceChain do
  it "AC 17: o saldo inicial informado entra como carregado do primeiro mês" do
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 200_000)
    expect(described_class.carried_into(month: Date.new(2026, 3, 1))).to eq(200_000)
  end

  it "AC 16: março encerrado com saldo atual 2.800 → abril carrega 2.800; fechado em −300 → abril carrega −300" do
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))
    Expense.create!(name: "gastos", amount_cents: 220_000, date: Date.new(2026, 3, 10),
                    payment_method: "debit", category: Category.create!(name: "geral"))
    expect(described_class.carried_into(month: Date.new(2026, 4, 1))).to eq(280_000)

    Expense.create!(name: "extra", amount_cents: 310_000, date: Date.new(2026, 3, 20),
                    payment_method: "cash", category: Category.find_by!(name: "geral"))
    expect(described_class.carried_into(month: Date.new(2026, 4, 1))).to eq(-30_000)
  end

  it "edge: saldo negativo se propaga por vários meses vazios" do
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: -30_000)
    expect(described_class.carried_into(month: Date.new(2026, 6, 1))).to eq(-30_000)
  end

  it "sem configuração ou antes do primeiro mês, o carregado é zero" do
    expect(described_class.carried_into(month: Date.new(2026, 3, 1))).to eq(0)
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 100)
    expect(described_class.carried_into(month: Date.new(2026, 2, 1))).to eq(0)
  end
end
