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
    expect(names).to eq [ "feira" ]
  end

  it "sorts by date then name" do
    Expense.create!(name: "b", amount_cents: 100, payment_method: "cash", category: others, date: Date.new(2026, 3, 20))
    Expense.create!(name: "a", amount_cents: 100, payment_method: "cash", category: others, date: Date.new(2026, 3, 5))
    expect(described_class.expenses(month: march).map(&:name)).to eq %w[a b]
  end

  # An installment has no date of its own, and falling back to the 1st of the
  # month collapsed every installment to the top of the list, above expenses
  # actually made earlier. It now sorts under the purchase's day-of-month — the
  # date the user recognises as "when this was bought". This is the contract the
  # expense list consumes — no other example mixes a dated row with an installment.
  it "sorts installments under the purchase's day of the month, among the dated expenses" do
    card = create_card!
    Expense.create!(name: "aaa", amount_cents: 100, payment_method: "cash",
                    category: others, date: Date.new(2026, 3, 2))
    Expense.create!(name: "bbb", amount_cents: 100, payment_method: "cash",
                    category: others, date: Date.new(2026, 3, 20))
    InstallmentPurchase.create!(name: "zzz", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))

    expect(described_class.expenses(month: march).map(&:name)).to eq [ "aaa", "zzz 1/10", "bbb" ]
  end

  # The purchase's day has no counterpart in a shorter month — the sort key is
  # clamped to the month's last day rather than blowing up on Date#change.
  it "clamps the purchase's day to a month that is shorter than it" do
    card = create_card!
    InstallmentPurchase.create!(name: "sofá", total_cents: 60_000, installments_count: 6,
                                card:, category: others, date: Date.new(2026, 3, 31))
    Expense.create!(name: "aaa", amount_cents: 100, payment_method: "cash",
                    category: others, date: Date.new(2026, 4, 5))

    expect(described_class.expenses(month: Date.new(2026, 4, 1)).map(&:name)).to eq [ "aaa", "sofá 2/6" ]
  end

  it "includes an installment whose competence lands months after the purchase" do
    card = create_card!
    InstallmentPurchase.create!(name: "sofá", total_cents: 60_000, installments_count: 6,
                                card:, category: others, date: Date.new(2026, 3, 10))

    expect(described_class.expenses(month: Date.new(2026, 6, 1)).map(&:name)).to eq [ "sofá 4/6" ]
  end
end
