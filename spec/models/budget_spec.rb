require "rails_helper"

RSpec.describe Budget do
  it "normaliza o mês para o dia 1º e exige valor não negativo" do
    budget = Budget.create!(category: category("mercado"), month: Date.new(2026, 3, 15), amount_cents: 90_000)
    expect(budget.month).to eq(Date.new(2026, 3, 1))
    expect(Budget.new(category: category("mercado"), month: Date.new(2026, 4, 1), amount_cents: -1)).not_to be_valid
    expect(Budget.new(category: category("padaria"), month: Date.new(2026, 4, 1), amount_cents: 0)).to be_valid
  end

  it "só admite um orçado por categoria e mês" do
    Budget.create!(category: category("mercado"), month: Date.new(2026, 3, 1), amount_cents: 90_000)
    expect(Budget.new(category: category("mercado"), month: Date.new(2026, 3, 31), amount_cents: 1)).not_to be_valid
  end

  it "recusa orçado manual na categoria reservada cartão de crédito (orçado dela é derivado)" do
    expect(Budget.new(category: credit_card_category, month: Date.new(2026, 3, 1), amount_cents: 1)).not_to be_valid
  end
end
