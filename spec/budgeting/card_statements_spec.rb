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

  it "lists the open statement and its successors ascending, and the closed ones descending" do
    credit_expense(1_000, Date.new(2026, 1, 2))  # January statement, due 12/01
    credit_expense(2_000, Date.new(2026, 3, 4))  # March statement, due 12/03
    credit_expense(3_000, Date.new(2026, 3, 6))  # April statement, due 13/04
    # Installments 1..3 land on the April, May and June statements.
    InstallmentPurchase.create!(name: "sofá", total_cents: 60_000, installments_count: 3,
                                date: Date.new(2026, 3, 6), card:, category: category("casa"))

    statements = described_class.new(card:, today: Date.new(2026, 3, 20))

    expect(statements.open.map { |row| row.statement.effective_due })
      .to eq [Date.new(2026, 4, 13), Date.new(2026, 5, 12), Date.new(2026, 6, 12)]
    expect(statements.closed.map { |row| row.statement.effective_due })
      .to eq [Date.new(2026, 3, 12), Date.new(2026, 1, 12)]
  end

  it "finds a statement by its nominal closing date, not its effective one" do
    credit_expense(5_000, Date.new(2026, 3, 6))
    row = described_class.new(card:, today: Date.new(2026, 3, 20)).find(Date.new(2026, 4, 5))

    expect(row.statement.effective_closing).to eq Date.new(2026, 4, 3)
    expect(row.total_cents).to eq 5_000
  end

  it "returns nil for a nominal closing with no statement" do
    credit_expense(5_000, Date.new(2026, 3, 6))

    expect(described_class.new(card:, today: Date.new(2026, 3, 20)).find(Date.new(2026, 9, 5))).to be_nil
  end

  it "keeps closed statements on the old validity window while later ones follow the new days" do
    card.card_schedules.create!(closing_day: 20, due_day: 27, valid_from: Date.new(2026, 3, 5))
    credit_expense(1_000, Date.new(2026, 3, 4))   # old window: closes 05/03, due 12/03
    credit_expense(2_000, Date.new(2026, 3, 10))  # new window: closes 20/03, due 27/03

    dues = described_class.new(card:, today: Date.new(2026, 4, 1)).rows.map { |row| row.statement.effective_due }

    expect(dues).to contain_exactly(Date.new(2026, 3, 12), Date.new(2026, 3, 27))
  end

  it "attributes a December purchase to the January statement of the next year" do
    credit_expense(9_000, Date.new(2026, 12, 10))
    row = described_class.new(card:, today: Date.new(2026, 12, 20)).rows.first

    expect(row.statement.nominal_closing).to eq Date.new(2027, 1, 5)
    expect(row.statement.effective_due).to eq Date.new(2027, 1, 12)
    # 05/12/2026 is a Saturday, so December closed on 04/12.
    expect(row.period_start).to eq Date.new(2026, 12, 4)
    expect(row.period_end).to eq Date.new(2027, 1, 4)
  end

  # Performance guard: attribution derives day by day, and each step used to hit
  # the database for the card's validity window — so the query count grew with
  # the number of rows (and with the length of each purchase period). The memo
  # threaded through the derivation must keep it constant.
  describe "query count" do
    def count_queries
      count = 0
      counter = lambda do |_name, _start, _finish, _id, payload|
        count += 1 unless payload[:name].in?(["SCHEMA", "TRANSACTION"]) || payload[:cached]
      end
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    def statements_for(months)
      other = create_card(name: "Card #{months}")
      months.times { |i| credit_expense(1_000, Date.new(2026, 1, 2) >> i, on: other) }
      described_class.new(card: other, today: Date.new(2026, 3, 20))
    end

    it "does not grow with the number of statements" do
      few = statements_for(2)
      many = statements_for(12)

      few_queries = count_queries { few.rows }
      many_queries = count_queries { many.rows }

      expect(many_queries).to eq(few_queries)
      expect(many_queries).to be <= 10
    end
  end

  it "identifies a statement in a URL by its nominal closing date" do
    statement = Budgeting::StatementAttribution.statement_for(card:, date: Date.new(2026, 3, 6))

    expect(statement.to_param).to eq "2026-04-05"
  end
end
