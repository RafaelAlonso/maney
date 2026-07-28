require "rails_helper"

RSpec.describe Budgeting::StatementAlert do
  let(:march) { Date.new(2026, 3, 1) }
  let(:card) { create_card }

  before { Setting.create!(first_month: march, initial_balance_cents: 0) }

  def alert(month = march) = described_class.new(month:, today: Date.new(2026, 3, 15))

  # A March credit purchase after the 05 closing lands on the statement due in April.
  def april_statement(amount)
    Expense.create!(name: "compra", amount_cents: amount, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: category)
  end

  def march_income(amount)
    Income.create!(name: "salário", amount_cents: amount, date: march)
  end

  it "is red when next month's statements exceed the current balance (AC 9)" do
    march_income(100_000)
    april_statement(120_000)
    expect(alert.level).to eq(:red)
  end

  it "is yellow at or above the threshold share of the balance (AC 9)" do
    march_income(100_000)
    april_statement(85_000) # 85% ≥ 80%
    expect(alert.level).to eq(:yellow)
  end

  it "is none below the threshold (AC 9)" do
    march_income(100_000)
    april_statement(70_000) # 70% < 80%
    expect(alert.level).to eq(:none)
  end

  it "respects a raised threshold (AC 10)" do
    Setting.instance.update!(alert_threshold_percent: 90)
    march_income(100_000)
    april_statement(85_000) # 85% < 90%
    expect(alert.level).to eq(:none)
  end

  it "is red on a non-positive balance with any statement (edge case)" do
    april_statement(50_000) # balance 0
    expect(alert.level).to eq(:red)
  end

  it "is none when there are no next-month statements" do
    march_income(100_000)
    expect(alert.level).to eq(:none)
  end
end
