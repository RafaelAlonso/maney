require "rails_helper"

RSpec.describe Budgeting::StatementsDue do
  let(:mercado) { category("mercado") }

  def credit_expense(amount, date, on:)
    Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                    card: on, category: mercado)
  end

  it "orders rows by the statement's effective due date" do
    # Azul closes 3 / due 10, Verde closes 15 / due 25 — both due in March, Azul first.
    azul = create_card(name: "Azul", closing_day: 3, due_day: 10)
    verde = create_card(name: "Verde", closing_day: 15, due_day: 25)
    credit_expense(76_000, Date.new(2026, 3, 5), on: verde)
    credit_expense(210_000, Date.new(2026, 3, 2), on: azul)

    rows = described_class.new(month: Date.new(2026, 3, 1)).rows

    expect(rows.map { |row| row.statement.card.name }).to eq %w[Azul Verde]
    expect(rows.map(&:amount_cents)).to eq [ 210_000, 76_000 ]
    expect(rows.map { |row| row.statement.effective_due })
      .to eq [ Date.new(2026, 3, 10), Date.new(2026, 3, 25) ]
  end

  it "breaks a same-day tie by card name" do
    roxo = create_card(name: "Roxo")
    azul = create_card(name: "Azul")
    credit_expense(10_000, Date.new(2026, 3, 4), on: roxo)
    credit_expense(20_000, Date.new(2026, 3, 4), on: azul)

    rows = described_class.new(month: Date.new(2026, 3, 1)).rows

    # Both cards use the reference schedule (closes 5, due 12) — same effective due.
    expect(rows.map { |row| row.statement.effective_due }.uniq).to eq [ Date.new(2026, 3, 12) ]
    expect(rows.map { |row| row.statement.card.name }).to eq %w[Azul Roxo]
  end

  it "keeps two cards sharing a name in a stable order, broken by id" do
    first = create_card(name: "Azul")
    second = create_card(name: "Azul")
    credit_expense(10_000, Date.new(2026, 3, 4), on: second)
    credit_expense(20_000, Date.new(2026, 3, 4), on: first)

    rows = described_class.new(month: Date.new(2026, 3, 1)).rows

    expect(rows.map { |row| row.statement.card.id }).to eq [ first.id, second.id ]
  end

  it "produces no rows and a zero total for a month with nothing due" do
    credit_expense(20_000, Date.new(2026, 3, 4), on: create_card)

    due = described_class.new(month: Date.new(2026, 1, 1))

    expect(due.rows).to be_empty
    expect(due.total_cents).to eq 0
  end

  it "totals the rows" do
    azul = create_card(name: "Azul", closing_day: 3, due_day: 10)
    roxo = create_card(name: "Roxo", closing_day: 8, due_day: 15)
    verde = create_card(name: "Verde", closing_day: 15, due_day: 25)
    credit_expense(210_000, Date.new(2026, 3, 2), on: azul)
    credit_expense(145_000, Date.new(2026, 3, 5), on: roxo)
    credit_expense(76_000, Date.new(2026, 3, 5), on: verde)

    expect(described_class.new(month: Date.new(2026, 3, 1)).total_cents).to eq 431_000
  end

  # A schedule change can leave two of one card's statements due in the same
  # calendar month, which is why a row is one statement and not one card.
  it "gives one card two rows when a schedule change puts two statements in one month" do
    card = create_card(name: "Azul", closing_day: 20, due_day: 10)
    card.card_schedules.create!(closing_day: 5, due_day: 25, valid_from: Date.new(2026, 8, 1))
    credit_expense(40_000, Date.new(2026, 7, 10), on: card)
    credit_expense(15_000, Date.new(2026, 8, 3), on: card)

    due = described_class.new(month: Date.new(2026, 8, 1))

    expect(due.rows.map { |row| row.statement.effective_due })
      .to eq [ Date.new(2026, 8, 10), Date.new(2026, 8, 25) ]
    expect(due.rows.map(&:amount_cents)).to eq [ 40_000, 15_000 ]
    # Distinct URL ids, so each line still opens an unambiguous statement.
    expect(due.rows.map { |row| row.statement.to_param }).to eq %w[2026-07-20 2026-08-05]
    expect(due.total_cents).to eq 55_000
  end

  it "normalises any day of the month to that month" do
    credit_expense(20_000, Date.new(2026, 3, 4), on: create_card)

    expect(described_class.new(month: Date.new(2026, 3, 27)).total_cents).to eq 20_000
  end
end
