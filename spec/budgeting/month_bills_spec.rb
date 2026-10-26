require "rails_helper"

# Card Azul closes on day 5 and is due on day 12: a purchase on 04/03 lands on
# the statement due 12/03, one on 06/03 on the statement due 13/04.
RSpec.describe Budgeting::MonthBills do
  let(:march) { Date.new(2026, 3, 1) }
  let(:april) { Date.new(2026, 4, 1) }
  let(:card) { create_card! }

  before do
    create_setting!(first_month: march)
    create_reserved_categories!
    purchase(20_000, Date.new(2026, 3, 4))
    purchase(5_000, Date.new(2026, 3, 6))
  end

  def purchase(cents, date)
    Expense.create!(name: "compra", amount_cents: cents, date:, payment_method: "credit", card:, category: category)
  end

  def pay(cents, closing)
    Expense.create!(name: "fatura", amount_cents: cents, date: Date.new(2026, 3, 20), payment_method: "debit",
                    category: credit_card_category, statement_card: card, statement_closing_on: closing)
  end

  def rows(month, today) = described_class.new(month:, today:).rows

  it "lists the month's statements with their status" do
    pay(2_000, Date.new(2026, 4, 5))

    march_rows = rows(march, Date.new(2026, 3, 20))
    expect(march_rows.map { |row| [ row.statement.effective_due, row.amount_cents, row.status, row.overdue ] })
      .to eq [ [ Date.new(2026, 3, 12), 20_000, :unpaid, false ] ]

    april_row = rows(april, Date.new(2026, 3, 20)).first
    expect([ april_row.status, april_row.remaining_cents ]).to eq [ :partial, 3_000 ]
  end

  it "brings a past unpaid statement forward as overdue" do
    april_rows = rows(april, Date.new(2026, 4, 20))

    expect(april_rows.map { |row| [ row.statement.effective_due, row.overdue ] })
      .to eq [ [ Date.new(2026, 4, 13), false ], [ Date.new(2026, 3, 12), true ] ]
  end

  it "never lists an untracked statement as overdue" do
    Setting.instance.update!(statements_tracked_from: Date.new(2026, 3, 15))

    expect(rows(april, Date.new(2026, 4, 20)).map(&:overdue)).to eq [ false ]
  end

  it "drops a past statement once fully paid" do
    pay(20_000, Date.new(2026, 3, 5))

    expect(rows(april, Date.new(2026, 4, 20)).map { |row| row.statement.effective_due }).to eq [ Date.new(2026, 4, 13) ]
  end
end
