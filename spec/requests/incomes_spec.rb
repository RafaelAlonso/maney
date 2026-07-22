require "rails_helper"

RSpec.describe "Incomes", type: :request do
  before { create_setting!(initial_balance_cents: 10_000); create_reserved_categories! }

  it "creates an income (AC 3)" do
    post incomes_path, params: { income: { name: "salário", amount: "5.000,00", date: "2026-03-01" } }
    expect(Income.find_by(name: "salário").amount_cents).to eq 500_000
  end

  it "lists the month's incomes with the derived carried balance first (AC 18)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 4, 1))
    get incomes_path(month: "2026-04")
    expect(response.body).to include("saldo do mês anterior").and include("salário")
    expect(response.body.index("saldo do mês anterior")).to be < response.body.index("salário")
  end

  it "labels the first month's derived row as saldo inicial with a link to settings (AC 18)" do
    get incomes_path(month: "2026-03")
    expect(response.body).to include("saldo inicial").and include(edit_settings_path)
  end

  it "rejects invalid amounts (AC 14)" do
    post incomes_path, params: { income: { name: "x", amount: "0,00", date: "2026-03-01" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "blocks dates before the first month (AC 19)" do
    post incomes_path, params: { income: { name: "x", amount: "10,00", date: "2026-02-01" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("primeiro mês")
  end

  it "updates and destroys a real income" do
    income = Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))
    patch income_path(income), params: { income: { name: "salário líquido", amount: "4.800,00", date: "2026-03-01" } }
    expect(income.reload.amount_cents).to eq 480_000
    delete income_path(income)
    expect(Income.exists?(income.id)).to be false
  end
end
