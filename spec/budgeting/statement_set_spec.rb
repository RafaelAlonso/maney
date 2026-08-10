require "rails_helper"

RSpec.describe "Competence and StatementSet" do
  let(:card) { create_card }
  let(:mercado) { category("mercado") }

  def credit_expense(amount, date, cat: mercado, on: card)
    Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                    card: on, category: cat)
  end

  it "competence: a standalone expense consumes its date's month; installment k consumes the k-th month of the sequence" do
    expense = credit_expense(20_000, Date.new(2026, 3, 4))
    expect(Budgeting::Competence.month_of(expense)).to eq(Date.new(2026, 3, 1))

    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )
    months = purchase.expenses.order(:installment_number).map { |e| Budgeting::Competence.month_of(e) }
    expect(months.first).to eq(Date.new(2026, 3, 1))
    expect(months[1]).to eq(Date.new(2026, 4, 1))
    expect(months.last).to eq(Date.new(2026, 12, 1)) # AC 9: installment 10 consumes December/2026
  end

  it "competence with first installment 4: installment 4 consumes the purchase month (AC 11)" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10, first_installment: 4,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )
    months = purchase.expenses.order(:installment_number).map { |e| Budgeting::Competence.month_of(e) }
    expect(months.first).to eq(Date.new(2026, 3, 1))
    expect(months.last).to eq(Date.new(2026, 9, 1))
  end

  it "groups the card's expenses by statement and sums the right total" do
    a = credit_expense(20_000, Date.new(2026, 3, 4))
    b = credit_expense(10_000, Date.new(2026, 3, 4))
    c = credit_expense(5_000, Date.new(2026, 3, 6))
    groups = Budgeting::StatementSet.for_card(card:)
    totals = groups.transform_values { |expenses| expenses.sum(&:amount_cents) }
    march = groups.keys.find { |s| s.effective_due == Date.new(2026, 3, 12) }
    april = groups.keys.find { |s| s.effective_due == Date.new(2026, 4, 13) }
    expect(totals[march]).to eq(30_000)
    expect(totals[april]).to eq(5_000)
    expect(groups[march]).to contain_exactly(a, b)
    expect(groups[april]).to contain_exactly(c)
  end

  it "AC 14: statements from two cards due in the same month appear together in due_in" do
    card_b = create_card(name: "Roxo", closing_day: 5, due_day: 12)
    credit_expense(120_000, Date.new(2026, 3, 4))
    credit_expense(80_000, Date.new(2026, 3, 4), on: card_b)
    due = Budgeting::StatementSet.due_in(month: Date.new(2026, 3, 1))
    expect(due.values.flatten.sum(&:amount_cents)).to eq(200_000)
    expect(due.keys.map { |s| s.card.id }).to contain_exactly(card.id, card_b.id)
  end

  it "for_card groups a purchase's installments into distinct, consecutive statements, " \
     "and the competence diverges from the due month" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )
    expenses = purchase.expenses.order(:installment_number).to_a
    groups = Budgeting::StatementSet.for_card(card:)

    statement_by_expense = groups.each_with_object({}) do |(statement, group_expenses), acc|
      group_expenses.each { |expense| acc[expense.id] = statement }
    end

    # Closing day 5 / due day 12, with Calendar's business-day adjustment
    # (Task 7) already applied — verified via ruby -e before writing the test.
    expected_due_dates = [
      Date.new(2026, 4, 13), # Apr/12 falls on Sunday -> moves to Monday 13
      Date.new(2026, 5, 12),
      Date.new(2026, 6, 12),
      Date.new(2026, 7, 13), # Jul/12 falls on Sunday -> moves to Monday 13
      Date.new(2026, 8, 12),
      Date.new(2026, 9, 14), # Sep/12 falls on Saturday -> moves to Monday 14
      Date.new(2026, 10, 12),
      Date.new(2026, 11, 12),
      Date.new(2026, 12, 14), # Dec/12 falls on Saturday -> moves to Monday 14
      Date.new(2027, 1, 12)
    ]

    actual_due_dates = expenses.map { |expense| statement_by_expense.fetch(expense.id).effective_due }
    expect(actual_due_dates).to eq(expected_due_dates)
    expect(actual_due_dates.uniq.size).to eq(10) # one distinct statement per installment, no collision

    first_installment = expenses.first
    first_statement = statement_by_expense.fetch(first_installment.id)
    competence_month = Budgeting::Competence.month_of(first_installment)
    due_month = first_statement.effective_due.beginning_of_month
    expect(competence_month).to eq(Date.new(2026, 3, 1)) # consumes March (the purchase month)
    expect(due_month).to eq(Date.new(2026, 4, 1)) # but is only due in April
    expect(competence_month).not_to eq(due_month) # competence and due date diverge on purpose
  end

  it "for_card returns empty for a card with no credit expenses" do
    Expense.create!(name: "pix mercado", amount_cents: 5_000, date: Date.new(2026, 3, 4),
                     payment_method: "debit", category: mercado)
    Expense.create!(name: "feira", amount_cents: 3_000, date: Date.new(2026, 3, 5),
                     payment_method: "cash", category: mercado)
    expect(Budgeting::StatementSet.for_card(card:)).to eq({})
  end

  it "due_in returns empty for a month with no statement due" do
    credit_expense(20_000, Date.new(2026, 3, 4))
    expect(Budgeting::StatementSet.due_in(month: Date.new(2026, 1, 1))).to eq({})
  end

  it "Fix 1: a validity-window change within the window keeps statements with the same nominal closing in separate buckets" do
    # new validity window from 10/03, strictly between the two purchases below
    card.card_schedules.create!(closing_day: 5, due_day: 1, valid_from: Date.new(2026, 3, 10))

    before_change = credit_expense(90_000, Date.new(2026, 3, 8))
    after_change = credit_expense(9_000, Date.new(2026, 3, 15))

    groups = Budgeting::StatementSet.for_card(card:)

    # both fall on the same nominal closing — the scenario that collided before the fix
    expect(groups.keys.map(&:nominal_closing).uniq).to eq([ Date.new(2026, 4, 5) ])
    expect(groups.keys.size).to eq(2)

    april = groups.keys.find { |s| s.effective_due == Date.new(2026, 4, 13) }
    may = groups.keys.find { |s| s.effective_due == Date.new(2026, 5, 1) }

    expect(april).not_to eq(may)
    expect(groups[april]).to contain_exactly(before_change)
    expect(groups[may]).to contain_exactly(after_change)
  end

  it "labels a list of expenses with their statements, credit only, keyed by expense id" do
    roxo = create_card(name: "Roxo", closing_day: 20, due_day: 27)
    a = credit_expense(20_000, Date.new(2026, 3, 4))
    b = credit_expense(5_000, Date.new(2026, 3, 6), on: roxo)
    cash = Expense.create!(name: "feira", amount_cents: 3_000, date: Date.new(2026, 3, 4),
                           payment_method: "cash", category: mercado)
    purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 60_000, installments_count: 3,
                                           date: Date.new(2026, 3, 6), card:, category: category("casa"))
    third = purchase.expenses.find_by!(installment_number: 3)

    labels = Budgeting::StatementSet.labels_for([ a, b, cash, third ])

    expect(labels[a.id].effective_due).to eq Date.new(2026, 3, 12)
    expect(labels[b.id].effective_due).to eq Date.new(2026, 3, 27)
    expect(labels[third.id].effective_due).to eq Date.new(2026, 6, 12)
    expect(labels).not_to have_key(cash.id)
  end

  it "by_due_month buckets every card's statements by the month they fall due" do
    credit_expense(120_000, Date.new(2026, 3, 4)) # due 2026-03-12
    credit_expense(80_000, Date.new(2026, 3, 6))  # due 2026-04-13

    buckets = Budgeting::StatementSet.by_due_month
    totals = buckets.transform_values { |statements| statements.values.flatten.sum(&:amount_cents) }

    expect(totals[Date.new(2026, 3, 1)]).to eq 120_000
    expect(totals[Date.new(2026, 4, 1)]).to eq 80_000
  end

  it "due_in returns the same statements by_due_month buckets, and an empty hash for a quiet month" do
    credit_expense(120_000, Date.new(2026, 3, 4))

    expect(Budgeting::StatementSet.due_in(month: Date.new(2026, 3, 1)))
      .to eq Budgeting::StatementSet.by_due_month[Date.new(2026, 3, 1)]
    expect(Budgeting::StatementSet.due_in(month: Date.new(2026, 1, 1))).to eq({})
  end
end
