require "rails_helper"

# Card Azul closes on day 5 and is due on day 12. A purchase on 06/03/2026 lands
# on the statement with nominal closing 05/04 (effective 03/04, a Friday) and
# nominal due 12/04 — a Sunday, so it is effectively due 13/04.
RSpec.describe Budgeting::StatementPayments do
  let(:card) { create_card! }
  let(:april_closing) { Date.new(2026, 4, 5) }

  before do
    create_setting!
    create_reserved_categories!
  end

  def purchase(amount, date)
    Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                    card:, category: category("mercado"))
  end

  def pay(amount, date, closing: april_closing, account: Account.primary, linked: true)
    Expense.create!(name: "fatura", amount_cents: amount, date:,
                    payment_method: account.wallet? ? "cash" : "debit",
                    category: credit_card_category, account:,
                    statement_card: (card if linked), statement_closing_on: (closing if linked))
  end

  def payments = described_class.new(by_due_month: Budgeting::StatementSet.by_due_month)

  def statement_on(closing) = Budgeting::CardStatements.new(card:).find(closing).statement

  it "sums several linked payments, from different accounts, into one statement" do
    purchase(50_000, Date.new(2026, 3, 6))
    statement = statement_on(april_closing)

    pay(20_000, Date.new(2026, 4, 1))
    expect(payments.paid_cents(statement)).to eq(20_000)
    expect(payments.status(statement, 50_000)).to eq(:partial)
    expect(payments.remaining_cents(statement, 50_000)).to eq(30_000)

    pay(30_000, Date.new(2026, 4, 2), account: Account.create!(name: "Itaú"))
    expect(payments.status(statement, 50_000)).to eq(:paid)

    pay(5_000, Date.new(2026, 4, 3), account: Account.wallet)
    expect(payments.status(statement, 50_000)).to eq(:paid)
    expect(payments.remaining_cents(statement, 50_000)).to eq(0)
  end

  it "an unpaid statement is :unpaid" do
    purchase(50_000, Date.new(2026, 3, 6))
    expect(payments.status(statement_on(april_closing), 50_000)).to eq(:unpaid)
  end

  it "an early payment settles in the statement's due month" do
    purchase(50_000, Date.new(2026, 3, 6))
    pay(50_000, Date.new(2026, 3, 28))

    settled = payments.settled_by_month
    expect(settled[Date.new(2026, 4, 1)]).to eq(50_000)
    expect(settled[Date.new(2026, 3, 1)]).to eq(0)
    expect(payments.linked_paid_in(Date.new(2026, 3, 1))).to eq(50_000)
    expect(payments.unlinked_paid_in(Date.new(2026, 3, 1))).to eq(0)
  end

  it "unlinked payments settle by their own date (unchanged)" do
    purchase(50_000, Date.new(2026, 3, 6))
    pay(50_000, Date.new(2026, 3, 28), linked: false)

    settled = payments.settled_by_month
    expect(settled[Date.new(2026, 3, 1)]).to eq(50_000)
    expect(settled[Date.new(2026, 4, 1)]).to eq(0)
    expect(payments.unlinked_paid_in(Date.new(2026, 3, 1))).to eq(50_000)
    expect(payments.paid_cents(statement_on(april_closing))).to eq(0)
  end

  it "a payment whose statement vanished counts by its own date" do
    bought = purchase(50_000, Date.new(2026, 3, 6))
    payment = pay(50_000, Date.new(2026, 3, 28))
    bought.destroy!

    expect(payments.statement_for(payment)).to be_nil
    expect(payments.settled_by_month[Date.new(2026, 3, 1)]).to eq(50_000)
    expect(payments.linked_paid_in(Date.new(2026, 3, 1))).to eq(0)
    expect(payments.unlinked_paid_in(Date.new(2026, 3, 1))).to eq(50_000)
  end

  it "two statements with the same nominal closing resolve to the earlier due date" do
    # A new validity window from 10/03, between the two purchases: both land on
    # nominal closing 05/04, one due 13/04 (old window), one due 01/05 (new).
    card.card_schedules.create!(closing_day: 5, due_day: 1, valid_from: Date.new(2026, 3, 10))
    purchase(90_000, Date.new(2026, 3, 8))
    purchase(9_000, Date.new(2026, 3, 15))
    payment = pay(10_000, Date.new(2026, 4, 1))

    statements = Budgeting::StatementSet.for_card(card:).keys
    april = statements.find { |s| s.effective_due == Date.new(2026, 4, 13) }
    may = statements.find { |s| s.effective_due == Date.new(2026, 5, 1) }

    expect(payments.statement_for(payment)).to eq(april)
    expect(payments.paid_cents(april)).to eq(10_000)
    expect(payments.paid_cents(may)).to eq(0)
    expect(statement_on(april_closing)).to eq(april)
  end

  it "statements due before statements_tracked_from are :untracked" do
    purchase(50_000, Date.new(2026, 3, 6))
    Setting.instance.update!(statements_tracked_from: Date.new(2026, 5, 1))

    expect(payments.status(statement_on(april_closing), 50_000)).to eq(:untracked)
  end
end
