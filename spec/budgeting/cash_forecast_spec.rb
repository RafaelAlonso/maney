require "rails_helper"

RSpec.describe Budgeting::CashForecast do
  let(:march) { Date.new(2026, 3, 1) }
  let(:card) { create_card }
  let(:mercado) { category("mercado") }

  before { Setting.create!(first_month: march, initial_balance_cents: 0) }

  def summary(month = march) = Budgeting::MonthSummary.new(month:, today: Date.new(2026, 3, 15))

  def estimate(month = march) = described_class.estimated_balance_cents(summary(month))

  def salary(cents = 500_000, month = march)
    Income.create!(name: "salário", amount_cents: cents, date: month)
  end

  def budget(cents, cat: mercado, month: march)
    Budget.create!(category: cat, month:, amount_cents: cents)
  end

  def debit(cents, date, cat: mercado)
    Expense.create!(name: "gasto", amount_cents: cents, date:, payment_method: "debit", category: cat)
  end

  # Day 6 lands in the cycle closing 5 April, so the statement is due in April and
  # March's card term stays zero — the assertion then measures the category alone.
  def credit(cents, date = Date.new(2026, 3, 6), cat: mercado, on: card)
    Expense.create!(name: "compra", amount_cents: cents, date:, payment_method: "credit",
                    card: on, category: cat)
  end

  it "AC 1: subtracts a budgeted category in full when nothing has been spent" do
    salary
    budget(200_000)
    expect(estimate).to eq(300_000)
  end

  it "sums every ordinary category, not just the first" do
    salary
    budget(200_000)
    budget(100_000, cat: category("casa"))
    expect(estimate).to eq(500_000 - 300_000)
  end

  it "AC 2: stops subtracting the part of the budget that credit purchases have consumed" do
    salary
    budget(200_000)
    credit(80_000)
    # mercado: max(200.000 − 80.000, 0) vs cash 0 → 120.000; no statement due in March
    expect(estimate).to eq(500_000 - 120_000)
  end

  it "AC 3: takes the larger of the remaining budget and the cash actually spent" do
    salary
    budget(200_000)
    credit(80_000)
    debit(150_000, Date.new(2026, 3, 10))
    # mercado: max(200.000 − 80.000, 0) = 120.000 vs cash 150.000 → 150.000
    expect(estimate).to eq(500_000 - 150_000)
  end

  it "AC 4: subtracts nothing for a category whose credit purchases exceed its budget" do
    salary
    budget(200_000)
    credit(250_000)
    # mercado: max(200.000 − 250.000, 0) = 0 vs cash 0 → 0
    expect(estimate).to eq(500_000)
  end

  it "AC 5: subtracts a same-month statement exactly once — the old double count" do
    verde = create_card(name: "Verde", closing_day: 5, due_day: 15)
    salary
    credit(200_000, Date.new(2026, 3, 1), on: verde) # closes 05/03, due 15/03 → March
    # mercado contributes 0 (no budget, credit ate it); the statement contributes 2.000
    expect(estimate).to eq(300_000)
  end

  it "AC 6: a purchase whose statement is due next month moves the reduction to that month" do
    preto = create_card(name: "Preto", closing_day: 28, due_day: 10)
    salary
    credit(200_000, Date.new(2026, 3, 10), on: preto) # closes 28/03, due 10/04
    # An explicit zero budget for April isolates the statement. Without it, April
    # ALSO inherits March's 2.000 of spending as mercado's budget and subtracts
    # that too — expected behavior (unspent budget is assumed to leave as cash),
    # but it would make this assertion look like an uncaught double count.
    budget(0, month: Date.new(2026, 4, 1))

    expect(estimate).to eq(500_000)
    # April carries March's 5.000 forward as income and pays the statement
    expect(estimate(Date.new(2026, 4, 1))).to eq(300_000)
  end

  it "AC 7: an installment counts as credit against its category's remaining budget" do
    salary
    casa = category("casa")
    budget(50_000, cat: casa)
    InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card:, category: casa
    )
    # casa: 10.000 of installment this month → max(50.000 − 10.000, 0) = 40.000.
    # Bought on the 10th, so the first statement closes in April — nothing due in March.
    expect(estimate).to eq(500_000 - 40_000)
  end

  it "counts the reserved category's payments when they exceed the statements due" do
    salary
    credit(120_000, Date.new(2026, 3, 1)) # closes 05/03, due 12/03 → 1.200 due in March
    Expense.create!(name: "fatura azul", amount_cents: 150_000, date: Date.new(2026, 3, 12),
                    payment_method: "debit", category: credit_card_category)
    # card term = max(1.200 due, 1.500 paid) = 1.500; mercado contributes 0
    expect(estimate).to eq(500_000 - 150_000)
  end

  it "works when the reserved cartão de crédito category does not exist (Fix 2b)" do
    salary
    credit(120_000, Date.new(2026, 3, 1)) # due 12/03 → March

    expect(Category.where(role: "credit_card")).to be_empty
    expect(estimate).to eq(500_000 - 120_000)
  end

  it "spends against the carried balance as well as the month's income" do
    Setting.instance.update!(initial_balance_cents: 200_000)
    salary
    budget(100_000)
    expect(estimate).to eq(700_000 - 100_000)
  end

  it "goes negative rather than clamping" do
    salary(100_000)
    budget(120_000)
    expect(estimate).to eq(-20_000)
  end
end
