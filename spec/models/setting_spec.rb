require "rails_helper"

RSpec.describe Setting do
  it "is a singleton with a normalized first month and a possibly negative initial balance" do
    setting = Setting.create!(first_month: Date.new(2026, 3, 15), initial_balance_cents: -30_000)
    expect(setting.first_month).to eq(Date.new(2026, 3, 1))
    expect(Setting.instance).to eq(setting)
    expect(Setting.new(first_month: Date.new(2026, 4, 1), initial_balance_cents: 0)).not_to be_valid
  end

  it "Fix 3: refuses to move first_month past an existing entry" do
    setting = Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
    Income.create!(name: "salário", amount_cents: 300_000, date: Date.new(2026, 1, 10))

    setting.first_month = Date.new(2026, 2, 1)
    expect(setting).not_to be_valid
    expect(setting.errors[:first_month]).to be_present

    setting.reload
    expect(setting.first_month).to eq(Date.new(2026, 1, 1))
  end

  it "Fix 3: still free to move first_month to an earlier date, even with entries" do
    setting = Setting.create!(first_month: Date.new(2026, 2, 1), initial_balance_cents: 0)
    Income.create!(name: "salário", amount_cents: 300_000, date: Date.new(2026, 2, 10))

    setting.first_month = Date.new(2026, 1, 1)
    expect(setting).to be_valid
  end

  it "Fix 3: with no entries, first_month stays free to move in any direction" do
    setting = Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
    setting.first_month = Date.new(2026, 6, 1)
    expect(setting).to be_valid
  end
end
