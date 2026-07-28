require "rails_helper"

RSpec.describe "Home month view", type: :request do
  let(:march) { Date.new(2026, 3, 1) }
  before { create_setting!(first_month: march); create_reserved_categories! }

  it "shows both balances, the credit-card line and the AC 2 numbers" do
    mercado = Category.create!(name: "mercado")
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 400_000)
    Expense.create!(name: "feira", amount_cents: 100_000, date: Date.new(2026, 3, 5),
                    payment_method: "debit", category: mercado)
    card = create_card!
    # 120.000 credit purchase closing 05/03, due 12/03 → statement in March
    Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card:, category: mercado)
    get root_path(month: "2026-03")
    expect(response.body).to include("saldo estimado").and include("saldo atual")
    expect(response.body).to include("cartão de crédito")
    # estimate = 5000 − max(4000, spent) − 1200 = −200 ; current = 5000 − 1000 debit = 4000
    expect(response.body).to include("-R$ 200,00").and include("R$ 4.000,00")
  end

  it "reflects a statement payment in the current balance, not the estimate (AC 2)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    Expense.create!(name: "fatura", amount_cents: 120_000, date: Date.new(2026, 3, 12),
                    payment_method: "debit", category: credit_card_category)
    get root_path(month: "2026-03")
    # current = 5000 − 1200 payment = 3800 (no other debit); estimate unaffected by the payment
    expect(response.body).to include("R$ 3.800,00")
  end

  it "highlights a category that overran its budget (AC 3)" do
    mercado = Category.create!(name: "mercado")
    Budget.create!(category: mercado, month: march, amount_cents: 90_000)
    Expense.create!(name: "feira", amount_cents: 150_000, date: Date.new(2026, 3, 5),
                    payment_method: "debit", category: mercado)
    get root_path(month: "2026-03")
    expect(response.body).to match(/text-red-700[^>]*>\s*gasto R\$ 1\.500,00/)
  end

  it "opens an empty month with zeros and no error (AC 12)" do
    Category.create!(name: "mercado")
    get root_path(month: "2026-03")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("orçado R$ 0,00")
  end

  it "carries the previous month's closing balance into the next, live (AC 6/7)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march) # March closes at 5000
    get root_path(month: "2026-04")
    expect(response.body).to include("R$ 5.000,00") # April current balance = carried 5000
    Expense.create!(name: "retro", amount_cents: 30_000, date: Date.new(2026, 3, 20),
                    payment_method: "debit", category: Category.create!(name: "mercado"))
    get root_path(month: "2026-04")
    expect(response.body).to include("R$ 4.700,00") # retroactive March debit ripples forward
  end

  it "navigates to another month (AC 4)" do
    get root_path(month: "2026-04")
    expect(response.body).to include("04/2026")
  end

  it "clamps a month before the first month up to the first month" do
    get root_path(month: "2025-01")
    expect(response.body).to include("03/2026")
    expect(response.body).not_to include("01/2025")
  end

  it "shows the FAB with both actions" do
    get root_path
    expect(response.body).to include(new_expense_path).and include(new_income_path)
  end

  it "shows a red alert when next month's statements exceed the current balance (AC 9)" do
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).to include("ultrapassam o saldo atual")
  end

  it "shows a yellow alert at/above the threshold (AC 9)" do
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 85_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).to include("se aproximam do saldo atual")
  end

  it "shows no alert below the threshold (AC 9)" do
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 70_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).not_to include("saldo atual deste mês")
  end

  it "respects the configured threshold (AC 10)" do
    Setting.instance.update!(alert_threshold_percent: 90)
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 85_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).not_to include("se aproximam")
  end

  it "projects a future month: inherited budget and projected spending (AC 11)" do
    card = create_card!
    casa = Category.create!(name: "casa")
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                date: Date.new(2026, 3, 10), card:, category: casa)
    get root_path(month: "2026-06")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("06/2026")
    # casa spends 10.000 in June and inherits May's 10.000 as June's budget
    expect(response.body).to include("gasto R$ 100,00").and include("orçado R$ 100,00")
  end
end
