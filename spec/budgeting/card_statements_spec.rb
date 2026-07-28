require "rails_helper"

# Reference card Azul: closes on day 5, is due on day 12, first validity window
# from 01/01/2026. No Setting is created here (as in the other engine specs), so
# the expense timeline validation stays out of the way.
RSpec.describe Budgeting::CardStatements do
  let(:card) { create_card }

  def credit_expense(amount, date, on: card)
    Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                    card: on, category: category("mercado"))
  end

  it "builds one row per statement, with its expenses and their total" do
    a = credit_expense(20_000, Date.new(2026, 3, 4))
    b = credit_expense(10_000, Date.new(2026, 3, 4))
    c = credit_expense(5_000, Date.new(2026, 3, 6))

    rows = described_class.new(card:, today: Date.new(2026, 3, 20)).rows
    march = rows.find { |row| row.statement.effective_due == Date.new(2026, 3, 12) }
    april = rows.find { |row| row.statement.effective_due == Date.new(2026, 4, 13) }

    expect(march.expenses).to contain_exactly(a, b)
    expect(march.total_cents).to eq 30_000
    expect(april.expenses).to contain_exactly(c)
    expect(april.total_cents).to eq 5_000
  end

  # 05/04/2026 is a Sunday, so April closes on 03/04 (Friday) — the period ends
  # the day before that, and starts on March's effective closing.
  it "runs the purchase period from the previous effective closing to the day before this one" do
    credit_expense(5_000, Date.new(2026, 3, 6))
    row = described_class.new(card:, today: Date.new(2026, 3, 20)).rows.first

    expect(row.period_start).to eq Date.new(2026, 3, 5)
    expect(row.period_end).to eq Date.new(2026, 4, 2)
  end

  it "anchors the earliest statement's period at the card's first validity window" do
    credit_expense(5_000, Date.new(2026, 1, 2))
    row = described_class.new(card:, today: Date.new(2026, 3, 20)).rows.first

    expect(row.period_start).to eq Date.new(2026, 1, 1)
    expect(row.period_end).to eq Date.new(2026, 1, 4)
  end

  it "has no rows for a card with no credit expense" do
    statements = described_class.new(card:, today: Date.new(2026, 3, 20))

    expect(statements).to be_empty
    expect(statements.rows).to eq []
  end
end
