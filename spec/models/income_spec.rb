require "rails_helper"

RSpec.describe Income do
  it "requires a name, a positive amount and a date" do
    expect(Income.new(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))).to be_valid
    expect(Income.new(name: "salário", amount_cents: 0, date: Date.new(2026, 3, 1))).not_to be_valid
    expect(Income.new(name: "salário", amount_cents: -1, date: Date.new(2026, 3, 1))).not_to be_valid
    expect(Income.new(name: "", amount_cents: 1, date: Date.new(2026, 3, 1))).not_to be_valid
    expect(Income.new(name: "salário", amount_cents: 1, date: nil)).not_to be_valid
  end

  it "blocks an income with a date before the first month (entry's AC 19 is a domain rule)" do
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    expect(Income.new(name: "x", amount_cents: 1, date: Date.new(2026, 2, 28))).not_to be_valid
    expect(Income.new(name: "x", amount_cents: 1, date: Date.new(2026, 3, 1))).to be_valid
  end
end
