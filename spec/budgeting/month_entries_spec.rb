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
end
