require "rails_helper"

RSpec.describe Budgeting::YearAnalysis do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }
  let(:mercado) { Category.create!(name: "mercado") }
  let(:march) { Date.new(2026, 3, 1) }
  let(:july) { Date.new(2026, 7, 1) }

  # July 2026: months before March are before the timeline, months after July
  # have not been reached. Both are inactive.
  def analysis(year: 2026, today: Date.new(2026, 7, 15))
    described_class.new(year:, today:)
  end

  # `card:` is not optional decoration: Expense#card_matches_method rejects a
  # credit expense with no card, so a credit case must pass one at create time.
  def spend(cents, on:, category:, method: "debit", card: nil)
    Expense.create!(name: "gasto", amount_cents: cents, payment_method: method,
                    category:, date: on, card:)
  end

  describe "the active month mask" do
    it "excludes months before the first month and months not yet reached" do
      expect(analysis.active_months).to eq((3..7).map { |m| Date.new(2026, m, 1) })
    end

    it "treats a fully past year as entirely active" do
      # Year 2026 itself can never be "entirely active": its own first two months
      # precede first_month (March 2026), no matter how far today advances. A
      # fully-past year has to start after first_month, so this uses 2027 — same
      # pairing (year 2027, today into 2028) as the installments-by-year test below.
      expect(analysis(year: 2027, today: Date.new(2028, 1, 1)).active_months.size).to eq 12
    end

    it "treats a year entirely before the first month as having no active months" do
      expect(analysis(year: 2025).active_months).to be_empty
    end
  end

  describe "spending by competence" do
    it "counts a dated expense in its own month" do
      spend(5_000, on: Date.new(2026, 3, 10), category: mercado)

      expect(analysis.spending.cents(march)).to eq 5_000
      expect(analysis.spending.cents(Date.new(2026, 4, 1))).to eq 0
    end

    it "counts a credit purchase in its purchase month, not its due month (AC 4)" do
      # Bought on the 28th, after the card closes on the 5th — the statement it
      # lands on is due in May, but the money was consumed in March.
      spend(8_000, on: Date.new(2026, 3, 28), category: mercado, method: "credit", card: create_card!)

      expect(analysis.spending.cents(march)).to eq 8_000
    end

    it "excludes the reserved credit-card category from spending (AC 4)" do
      spend(40_000, on: Date.new(2026, 3, 12), category: credit_card_category)

      expect(analysis.spending.cents(march)).to eq 0
      expect(analysis.categories).not_to include(credit_card_category)
    end

    # Regression: `where.not(categories: { role: "credit_card" })` silently drops
    # every NULL-role category under SQL three-valued logic. Most categories are
    # NULL-role, so that bug empties the chart.
    it "includes categories whose role is NULL" do
      expect(mercado.role).to be_nil
      spend(3_000, on: Date.new(2026, 3, 4), category: mercado)

      expect(analysis.spending_by_category[mercado].cents(march)).to eq 3_000
    end

    it "spreads an installment purchase across its competence months" do
      card = create_card!
      InstallmentPurchase.create!(name: "sofá", total_cents: 90_000, installments_count: 3,
                                  card:, category: mercado, date: Date.new(2026, 3, 10))

      expect(analysis.spending.cents(march)).to eq 30_000
      expect(analysis.spending.cents(Date.new(2026, 4, 1))).to eq 30_000
      expect(analysis.spending.cents(Date.new(2026, 5, 1))).to eq 30_000
    end

    it "counts only the installments falling inside the year" do
      card = create_card!
      InstallmentPurchase.create!(name: "notebook", total_cents: 120_000, installments_count: 12,
                                  card:, category: mercado, date: Date.new(2026, 11, 5))

      past = described_class.new(year: 2026, today: Date.new(2027, 6, 1))
      next_year = described_class.new(year: 2027, today: Date.new(2028, 1, 1))

      # Nov and Dec 2026 here; the remaining ten fall in 2027.
      expect(past.spending.total_cents).to eq 20_000
      expect(next_year.spending.total_cents).to eq 100_000
    end

    # A series joined partway through: `first_installment: 3` of 6 creates only
    # installments 3..6, and Competence anchors installment 3 on the purchase
    # month. The amount is still split by the full count, so the four rows come
    # to R$ 800 of a R$ 1.200 purchase — the first two were paid elsewhere and
    # this app never saw them.
    it "anchors a series joined partway through on its purchase month" do
      InstallmentPurchase.create!(name: "curso", total_cents: 120_000, installments_count: 6,
                                  card: create_card!, category: mercado,
                                  date: Date.new(2026, 5, 10), first_installment: 3)

      subject = described_class.new(year: 2026, today: Date.new(2026, 12, 31))
      expect(subject.spending.cents(Date.new(2026, 4, 1))).to eq 0
      expect(subject.spending.cents(Date.new(2026, 5, 1))).to eq 20_000
      expect(subject.spending.cents(Date.new(2026, 8, 1))).to eq 20_000
      expect(subject.spending.total_cents).to eq 80_000
    end

    it "omits a category from a month with no spending" do
      spend(3_000, on: Date.new(2026, 3, 4), category: mercado)

      values = analysis.spending_by_category[mercado].values_for_chart
      expect(values[2]).to eq 3_000
      expect(values[3]).to eq 0
      expect(analysis.spending_by_category).not_to have_key(others)
    end

    it "orders categories by year total, descending" do
      spend(1_000, on: Date.new(2026, 3, 4), category: others)
      spend(9_000, on: Date.new(2026, 4, 4), category: mercado)

      expect(analysis.categories).to eq [ mercado, others ]
    end

    it "keeps future months empty even when installments are committed to them (AC 10)" do
      InstallmentPurchase.create!(name: "sofá", total_cents: 60_000, installments_count: 6,
                                  card: create_card!, category: mercado, date: Date.new(2026, 6, 10))

      # June and July are active; August onwards is not yet reached.
      expect(analysis.spending.cents(Date.new(2026, 7, 1))).to eq 10_000
      expect(analysis.spending.values_for_chart[7]).to be_nil
      # ...and the four committed future months never touch the average:
      # R$ 200 over the five active months March..July.
      expect(analysis.spending.average_cents).to eq 4_000
    end
  end

  describe "income, cash outflow and profit" do
    it "counts income rows in their own month" do
      Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 5))

      expect(analysis.income.cents(march)).to eq 500_000
    end

    # The carried balance is last month's leftover, not income earned this month.
    # Including it (as MonthSummary#incomes_total_cents does, for a different
    # question) would compound across the year.
    it "excludes the carried balance from income" do
      # Setting#single_row forbids a second row, so update the one the `before`
      # block already created rather than creating another.
      Setting.instance.update!(initial_balance_cents: 1_000_000)
      Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 4, 5))

      expect(analysis.income.cents(Date.new(2026, 4, 1))).to eq 500_000
    end

    it "counts debit and cash as outflow and never credit" do
      spend(7_000, on: Date.new(2026, 3, 2), category: mercado, method: "debit")
      spend(2_000, on: Date.new(2026, 3, 3), category: mercado, method: "cash")
      spend(90_000, on: Date.new(2026, 3, 4), category: mercado, method: "credit", card: create_card!)

      expect(analysis.cash_outflow.cents(march)).to eq 9_000
    end

    # A statement payment is an expense in the reserved category paid by debit —
    # it is real money leaving, so outflow counts it even though spending does not.
    it "includes an entered statement payment in cash outflow" do
      spend(40_000, on: Date.new(2026, 3, 12), category: credit_card_category, method: "debit")

      expect(analysis.cash_outflow.cents(march)).to eq 40_000
      expect(analysis.spending.cents(march)).to eq 0
    end

    it "reports profit both ways, and negative when income falls short (AC 7)" do
      Income.create!(name: "salário", amount_cents: 100_000, date: Date.new(2026, 3, 5))
      spend(30_000, on: Date.new(2026, 3, 6), category: mercado, method: "debit")
      spend(150_000, on: Date.new(2026, 3, 7), category: mercado, method: "credit", card: create_card!)

      # Spending counts the credit purchase in March; outflow does not.
      expect(analysis.profit_vs_spending.cents(march)).to eq(-80_000)
      expect(analysis.profit_vs_outflow.cents(march)).to eq 70_000
    end

    it "has no data when the year holds nothing (AC 11)" do
      expect(analysis).not_to be_any_data
    end

    it "has no data when the year is entirely before the first month" do
      spend(5_000, on: Date.new(2026, 3, 10), category: mercado)

      expect(analysis(year: 2025)).not_to be_any_data
    end

    it "has data when only income exists" do
      Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 5))

      expect(analysis).to be_any_data
    end
  end

  describe "the story's edge cases" do
    # Deleting a category reassigns its expenses to the default one
    # (CategoriesController#destroy), so the charts show current categorisation
    # for the whole year. This is behaviour to confirm, not to build.
    it "shows a deleted category's history under the default category" do
      spend(5_000, on: Date.new(2026, 3, 4), category: mercado)
      mercado.expenses.update_all(category_id: others.id)
      mercado.reload.destroy!

      expect(analysis.spending_by_category[others].cents(march)).to eq 5_000
      expect(analysis.categories.map(&:name)).to eq [ "outros" ]
    end

    it "reports zero for a category's months before its first expense" do
      lazer = Category.create!(name: "lazer")
      spend(5_000, on: Date.new(2026, 6, 4), category: lazer)

      series = analysis.spending_by_category[lazer]
      expect(series.cents(march)).to eq 0
      expect(series.cents(Date.new(2026, 6, 1))).to eq 5_000
    end

    it "averages over three months when only three months have data" do
      spend(3_000, on: Date.new(2026, 3, 4), category: mercado)
      spend(6_000, on: Date.new(2026, 4, 4), category: mercado)

      subject = described_class.new(year: 2026, today: Date.new(2026, 5, 20))
      # March, April and May are active; May is a real zero.
      expect(subject.spending.average_cents).to eq 3_000
    end

    it "reads a year with spending and no income as a full loss, not as no data" do
      spend(5_000, on: Date.new(2026, 3, 4), category: mercado)

      expect(analysis).to be_any_data
      expect(analysis.profit_vs_spending.cents(march)).to eq(-5_000)
    end
  end
end
