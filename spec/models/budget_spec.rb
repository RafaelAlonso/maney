require "rails_helper"

RSpec.describe Budget do
  it "normalizes the month to the 1st and requires a non-negative amount" do
    budget = Budget.create!(category: category("mercado"), month: Date.new(2026, 3, 15), amount_cents: 90_000)
    expect(budget.month).to eq(Date.new(2026, 3, 1))
    expect(Budget.new(category: category("mercado"), month: Date.new(2026, 4, 1), amount_cents: -1)).not_to be_valid
    expect(Budget.new(category: category("padaria"), month: Date.new(2026, 4, 1), amount_cents: 0)).to be_valid
  end

  it "allows only one budget per category and month" do
    Budget.create!(category: category("mercado"), month: Date.new(2026, 3, 1), amount_cents: 90_000)
    expect(Budget.new(category: category("mercado"), month: Date.new(2026, 3, 31), amount_cents: 1)).not_to be_valid
  end

  it "refuses a manual budget on the reserved credit-card category (its budget is derived)" do
    expect(Budget.new(category: credit_card_category, month: Date.new(2026, 3, 1), amount_cents: 1)).not_to be_valid
  end
end
