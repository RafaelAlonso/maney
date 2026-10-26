require "rails_helper"

RSpec.describe Income do
  # An income needs the Conta principal a Setting creates.
  before { create_setting! }

  it "requires a name, a positive amount and a date" do
    expect(Income.new(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))).to be_valid
    expect(Income.new(name: "salário", amount_cents: 0, date: Date.new(2026, 3, 1))).not_to be_valid
    expect(Income.new(name: "salário", amount_cents: -1, date: Date.new(2026, 3, 1))).not_to be_valid
    expect(Income.new(name: "", amount_cents: 1, date: Date.new(2026, 3, 1))).not_to be_valid
    expect(Income.new(name: "salário", amount_cents: 1, date: nil)).not_to be_valid
  end

  it "blocks an income with a date before the first month (entry's AC 19 is a domain rule)" do
    expect(Income.new(name: "x", amount_cents: 1, date: Date.new(2026, 2, 28))).not_to be_valid
    expect(Income.new(name: "x", amount_cents: 1, date: Date.new(2026, 3, 1))).to be_valid
  end

  describe "account" do
    it "defaults to the primary account" do
      income = Income.create!(name: "salário", amount_cents: 1, date: Date.new(2026, 3, 1))
      expect(income.account).to eq(Account.primary)
    end

    it "accepts the wallet" do
      income = Income.create!(name: "troco", amount_cents: 1, date: Date.new(2026, 3, 1), account: Account.wallet)
      expect(income.reload.account).to eq(Account.wallet)
    end
  end
end
