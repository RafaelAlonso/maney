require "rails_helper"

RSpec.describe Budgeting::CategoryYear do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:card) { create_card! }
  let(:march) { Date.new(2026, 3, 1) }

  # July 2026: months before March precede the timeline, months after July have
  # not been reached. Both are inactive.
  def category_year(category: mercado, year: 2026, today: Date.new(2026, 7, 15))
    described_class.new(category:, year:, today:)
  end

  def spend(cents, on:, category: mercado, method: "debit", card: nil)
    Expense.create!(name: "gasto", amount_cents: cents, payment_method: method,
                    category:, date: on, card:)
  end

  it "totals the category's spending month by month (AC 1)" do
    spend(5_000, on: Date.new(2026, 3, 10))
    spend(2_000, on: Date.new(2026, 3, 20))
    spend(1_000, on: Date.new(2026, 4, 2))

    expect(category_year.spending.cents(march)).to eq 7_000
    expect(category_year.spending.cents(Date.new(2026, 4, 1))).to eq 1_000
  end

  it "ignores other categories' spending" do
    spend(9_000, on: Date.new(2026, 3, 10), category: Category.create!(name: "padaria"))

    expect(category_year.spending.cents(march)).to eq 0
    expect(category_year).not_to be_any_data
  end

  it "counts a credit purchase in its purchase month (AC 5)" do
    spend(8_000, on: Date.new(2026, 3, 28), method: "credit", card:)

    expect(category_year.spending.cents(march)).to eq 8_000
  end

  it "counts each installment in its own month with its own amount (AC 6)" do
    InstallmentPurchase.create!(name: "sofá", total_cents: 90_000, installments_count: 3,
                                card:, category: mercado, date: Date.new(2026, 3, 10))

    expect(category_year.spending.cents(march)).to eq 30_000
    expect(category_year.spending.cents(Date.new(2026, 4, 1))).to eq 30_000
    expect(category_year.spending.cents(Date.new(2026, 5, 1))).to eq 30_000
  end

  # A NULL-role category is the ordinary case; the `where.not` trap would drop
  # every one of them.
  it "works for a category whose role is NULL" do
    expect(mercado.role).to be_nil
    spend(3_000, on: Date.new(2026, 3, 4))

    expect(category_year.spending.cents(march)).to eq 3_000
  end

  # Decision 1: the reserved category is excluded from the *year* screen, where
  # counting it would double-count consumption. On its own screen its content is
  # the statement payments the list below already shows, and no branch is needed
  # to get them — a statement payment is debit or cash with a real date.
  it "charts the reserved category's statement payments" do
    spend(40_000, on: Date.new(2026, 3, 12), category: credit_card_category)

    subject = category_year(category: credit_card_category)
    expect(subject.spending.cents(march)).to eq 40_000
    expect(subject).to be_any_data
  end

  it "leaves months before the first month and months not yet reached empty (AC 7)" do
    spend(6_000, on: Date.new(2026, 3, 4))

    values = category_year.spending.values_for_chart
    expect(values[0]).to be_nil   # January — before the first month
    expect(values[1]).to be_nil   # February — before the first month
    expect(values[3]).to eq 0     # April — happened, nothing spent
    expect(values[7]).to be_nil   # August — not yet reached
  end

  it "averages over the months that have data only (AC 1, AC 7)" do
    spend(6_000, on: Date.new(2026, 3, 4))
    spend(4_000, on: Date.new(2026, 4, 4))

    # (6000 + 4000 + 0 + 0 + 0) / 5 active months, March through July.
    expect(category_year.spending.average_cents).to eq 2_000
  end

  it "keeps only the in-year part of a series crossing the year boundary" do
    InstallmentPurchase.create!(name: "geladeira", total_cents: 120_000, installments_count: 4,
                                card:, category: mercado, date: Date.new(2026, 11, 10))

    subject = category_year(year: 2027, today: Date.new(2027, 6, 1))
    expect(subject.spending.cents(Date.new(2027, 1, 1))).to eq 30_000
    expect(subject.spending.cents(Date.new(2027, 2, 1))).to eq 30_000
    expect(subject.spending.cents(Date.new(2027, 3, 1))).to eq 0
  end

  it "reports no data for a year the category never touched" do
    spend(5_000, on: Date.new(2026, 3, 10))

    expect(category_year(year: 2027, today: Date.new(2027, 6, 1))).not_to be_any_data
  end

  # The guardrail, made structural: the drill-down and the year screen must
  # never disagree about what a category spent.
  it "matches YearAnalysis's slice for an ordinary category, month for month" do
    today = Date.new(2026, 7, 15)
    spend(5_000, on: Date.new(2026, 3, 10))
    spend(1_200, on: Date.new(2026, 6, 2))
    InstallmentPurchase.create!(name: "sofá", total_cents: 90_000, installments_count: 3,
                                card:, category: mercado, date: Date.new(2026, 4, 10))

    slice = Budgeting::YearAnalysis.new(year: 2026, today:).spending_by_category.fetch(mercado)
    subject = category_year(today:)

    slice.months.each do |month|
      expect(subject.spending.cents(month)).to eq(slice.cents(month)), "mismatch in #{month}"
    end
    expect(subject.spending.average_cents).to eq slice.average_cents
  end
end
