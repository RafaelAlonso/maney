require "rails_helper"

RSpec.describe Budgeting::CompetenceSpending do
  # 2025, not the helper's default 2026-03: one example needs an expense dated
  # before the year under test, and Expense#date_rules rejects any date earlier
  # than first_month.
  before { create_setting!(first_month: Date.new(2025, 1, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:card) { create_card! }

  def entries(scope: Expense.all, year: 2026)
    described_class.entries(scope:, year:)
  end

  # `card:` is not optional decoration: Expense#card_matches_method rejects a
  # credit expense with no card.
  def spend(cents, on:, category: mercado, method: "debit", card: nil)
    Expense.create!(name: "gasto", amount_cents: cents, payment_method: method,
                    category:, date: on, card:)
  end

  it "counts a dated expense in its own month" do
    expense = spend(5_000, on: Date.new(2026, 3, 10))

    expect(entries).to eq [ [ expense, Date.new(2026, 3, 1) ] ]
  end

  it "counts a credit purchase in its purchase month, not its due month" do
    # Bought on the 28th, after the card closes on the 5th: the statement it
    # lands on is due in May, but the money was consumed in March.
    expense = spend(8_000, on: Date.new(2026, 3, 28), method: "credit", card:)

    expect(entries).to eq [ [ expense, Date.new(2026, 3, 1) ] ]
  end

  it "excludes expenses dated outside the year" do
    spend(5_000, on: Date.new(2025, 12, 31))
    spend(5_000, on: Date.new(2027, 1, 1))

    expect(entries).to be_empty
  end

  # Installments carry date: nil, so a date-range query cannot see them at all.
  it "places each installment in its own competence month" do
    InstallmentPurchase.create!(name: "sofá", total_cents: 90_000, installments_count: 3,
                                card:, category: mercado, date: Date.new(2026, 3, 10))

    months = entries.map(&:last)
    expect(months).to contain_exactly(Date.new(2026, 3, 1), Date.new(2026, 4, 1), Date.new(2026, 5, 1))
  end

  it "keeps only the in-year installments of a series crossing the year boundary" do
    InstallmentPurchase.create!(name: "geladeira", total_cents: 120_000, installments_count: 4,
                                card:, category: mercado, date: Date.new(2026, 11, 10))

    expect(entries.map(&:last)).to contain_exactly(Date.new(2026, 11, 1), Date.new(2026, 12, 1))
    expect(entries(year: 2027).map(&:last)).to contain_exactly(Date.new(2027, 1, 1), Date.new(2027, 2, 1))
  end

  it "honours the scope it is given" do
    padaria = Category.create!(name: "padaria")
    spend(5_000, on: Date.new(2026, 3, 10))
    kept = spend(700, on: Date.new(2026, 3, 11), category: padaria)

    expect(entries(scope: padaria.expenses)).to eq [ [ kept, Date.new(2026, 3, 1) ] ]
  end

  # Regression: `where.not(categories: { role: "credit_card" })` silently drops
  # every NULL-role category under SQL three-valued logic, and most categories
  # are NULL-role. The NOT IN subquery form must survive this extraction.
  it "keeps NULL-role categories when the caller excludes the reserved one" do
    expect(mercado.role).to be_nil
    expense = spend(3_000, on: Date.new(2026, 3, 4))
    spend(40_000, on: Date.new(2026, 3, 12), category: credit_card_category)

    scope = Expense.where.not(category: Category.where(role: "credit_card"))
    expect(entries(scope:)).to eq [ [ expense, Date.new(2026, 3, 1) ] ]
  end
end
