require "rails_helper"

RSpec.describe Budgeting::MonthSummary do
  let(:march) { Date.new(2026, 3, 1) }
  let(:card) { create_card }
  let(:mercado) { category("mercado") }

  before { Setting.create!(first_month: march, initial_balance_cents: 0) }

  def summary(month = march) = described_class.new(month:, today: Date.new(2026, 3, 15))

  def debit(amount, date, cat:, name: "gasto")
    Expense.create!(name:, amount_cents: amount, date:, payment_method: "debit", category: cat)
  end

  def credit(amount, date, cat: mercado)
    Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                    card:, category: cat)
  end

  it "AC 3: a credit purchase consumes the category in the purchase month and the credit-card budget in the due month — without touching the current balance" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    credit(20_000, Date.new(2026, 3, 4))
    expect(summary.spent_cents(mercado)).to eq(20_000)
    expect(summary.budgeted_cents(credit_card_category)).to eq(20_000) # statement due 12/03
    expect(summary(Date.new(2026, 4, 1)).spent_cents(mercado)).to eq(0) # doesn't debit again
    expect(summary.current_balance_cents).to eq(500_000)
  end

  it "AC 4: a purchase on 05/03 consumes March, but the credit-card budget counts only in April" do
    credit(30_000, Date.new(2026, 3, 5))
    expect(summary.spent_cents(mercado)).to eq(30_000)
    expect(summary.budgeted_cents(credit_card_category)).to eq(0)
    expect(summary(Date.new(2026, 4, 1)).budgeted_cents(credit_card_category)).to eq(30_000)
  end

  it "AC 12: income 5.000, budgeted 4.000, no statement in the month → estimate 1.000" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 250_000)
    Budget.create!(category: category("casa"), month: march, amount_cents: 150_000)
    expect(summary.estimated_balance_cents).to eq(100_000)
  end

  it "AC 13: budgeted 900 and spent 1.500 → the estimate uses max(budgeted, spent)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 90_000)
    debit(150_000, Date.new(2026, 3, 10), cat: mercado)
    expect(summary.estimated_balance_cents).to eq(500_000 - 150_000)
  end

  it "AC 14: statements from two cards (1.200 + 800) due in March → credit-card budget 2.000, within the estimate" do
    card_b = create_card(name: "Roxo", closing_day: 5, due_day: 12)
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    credit(120_000, Date.new(2026, 3, 4))
    Expense.create!(name: "compra", amount_cents: 80_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card: card_b, category: category("casa"))
    expect(summary.budgeted_cents(credit_card_category)).to eq(200_000)
    # estimate = 5.000 − (max per category): mercado 1.200 + casa 800 + card 2.000... the
    # spent of mercado/casa is by competence and their budget is zero — max = spent.
    expect(summary.estimated_balance_cents).to eq(500_000 - 120_000 - 80_000 - 200_000)
  end

  it "AC 15: credit never touches the current balance; paying a statement is a debit expense in the credit-card category" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    debit(100_000, Date.new(2026, 3, 8), cat: mercado)
    credit(120_000, Date.new(2026, 3, 4)) # statement closes 05/03, due 12/03 (March)
    credit(80_000, Date.new(2026, 3, 6))  # statement due 13/04
    expect(summary.current_balance_cents).to eq(400_000)

    debit(120_000, Date.new(2026, 3, 12), cat: credit_card_category, name: "fatura azul")
    expect(summary.current_balance_cents).to eq(280_000)
    expect(summary.spent_cents(credit_card_category)).to eq(120_000)
  end

  it "AC 18: a month with no expense — zero spent in every category and estimate = income − budgeted, without error" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 90_000)
    expect(summary.spent_cents(mercado)).to eq(0)
    expect(summary.spent_cents(credit_card_category)).to eq(0)
    expect(summary.estimated_balance_cents).to eq(410_000)
  end

  it "AC 16/17: the carried balance enters as the month's first income" do
    Setting.instance.update!(initial_balance_cents: 200_000)
    expect(summary.carried_balance_cents).to eq(200_000)
    expect(summary.incomes_total_cents).to eq(200_000)
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    expect(summary.incomes_total_cents).to eq(700_000)
  end

  it "Fix 2b: the credit-card budget enters the estimate even without the reserved category existing " \
     "(doesn't depend on credit_card_category having been called first)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    credit(120_000, Date.new(2026, 3, 4)) # statement closes 05/03, due 12/03 -> counts in March

    expect(Category.where(role: "credit_card")).to be_empty
    # committed = mercado max(0, 120.000) + card max(120.000, 0) = 240.000
    expect(summary.estimated_balance_cents).to eq(500_000 - 120_000 - 120_000)
  end

  it "installments consume their months: a sofá 10x from March consumes 100 in March and 100 in December" do
    InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )
    expect(summary.spent_cents(category("casa"))).to eq(10_000)
    expect(summary(Date.new(2026, 12, 1)).spent_cents(category("casa"))).to eq(10_000)
    expect(summary(Date.new(2027, 1, 1)).spent_cents(category("casa"))).to eq(0)
  end
end
