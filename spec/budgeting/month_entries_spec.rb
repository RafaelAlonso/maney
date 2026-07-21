require "rails_helper"

RSpec.describe Budgeting::MonthEntries do
  before do
    create_setting!
    create_reserved_categories!
  end

  let(:others) { Category.find_by!(role: "others") }
  let(:march) { Date.new(2026, 3, 1) }

  it "returns dated expenses of the month and installments by competence" do
    card = create_card!
    Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "debit",
                    category: others, date: Date.new(2026, 3, 10))
    Expense.create!(name: "abril", amount_cents: 1_000, payment_method: "cash",
                    category: others, date: Date.new(2026, 4, 2))
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))

    names = described_class.expenses(month: march).map(&:name)
    expect(names).to include("padaria", "sofá 1/10")
    expect(names).not_to include("abril", "sofá 2/10")
  end

  it "filters by category" do
    mercado = Category.create!(name: "mercado")
    Expense.create!(name: "feira", amount_cents: 2_000, payment_method: "cash",
                    category: mercado, date: Date.new(2026, 3, 5))
    Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "debit",
                    category: others, date: Date.new(2026, 3, 10))

    names = described_class.expenses(month: march, category: mercado).map(&:name)
    expect(names).to eq ["feira"]
  end

  it "sorts by date then name" do
    Expense.create!(name: "b", amount_cents: 100, payment_method: "cash", category: others, date: Date.new(2026, 3, 20))
    Expense.create!(name: "a", amount_cents: 100, payment_method: "cash", category: others, date: Date.new(2026, 3, 5))
    expect(described_class.expenses(month: march).map(&:name)).to eq %w[a b]
  end

  # A parcela não tem data própria: ordena como se fosse o dia 1º do mês, então
  # vem antes de qualquer gasto datado, mesmo com nome alfabeticamente maior.
  # É o contrato que a lista de gastos consome — nenhum outro exemplo mistura
  # linha datada com parcela.
  it "sorts installments as the first of the month, ahead of dated expenses" do
    card = create_card!
    Expense.create!(name: "aaa", amount_cents: 100, payment_method: "cash",
                    category: others, date: Date.new(2026, 3, 2))
    InstallmentPurchase.create!(name: "zzz", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))

    expect(described_class.expenses(month: march).map(&:name)).to eq ["zzz 1/10", "aaa"]
  end

  it "includes a parcela whose competence lands months after the purchase" do
    card = create_card!
    InstallmentPurchase.create!(name: "sofá", total_cents: 60_000, installments_count: 6,
                                card:, category: others, date: Date.new(2026, 3, 10))

    expect(described_class.expenses(month: Date.new(2026, 6, 1)).map(&:name)).to eq ["sofá 4/6"]
  end
end
