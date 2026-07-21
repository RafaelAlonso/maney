require "rails_helper"

RSpec.describe "Competence e StatementSet" do
  let(:card) { create_card }
  let(:mercado) { category("mercado") }

  def credit_expense(amount, date, cat: mercado, on: card)
    Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                    card: on, category: cat)
  end

  it "competência: gasto comum consome o mês da data; parcela k consome o k-ésimo mês da sequência" do
    expense = credit_expense(20_000, Date.new(2026, 3, 4))
    expect(Budgeting::Competence.month_of(expense)).to eq(Date.new(2026, 3, 1))

    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )
    months = purchase.expenses.order(:installment_number).map { |e| Budgeting::Competence.month_of(e) }
    expect(months.first).to eq(Date.new(2026, 3, 1))
    expect(months[1]).to eq(Date.new(2026, 4, 1))
    expect(months.last).to eq(Date.new(2026, 12, 1)) # AC 9: parcela 10 consome dezembro/2026
  end

  it "competência com parcela inicial 4: a parcela 4 consome o mês da compra (AC 11)" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10, first_installment: 4,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )
    months = purchase.expenses.order(:installment_number).map { |e| Budgeting::Competence.month_of(e) }
    expect(months.first).to eq(Date.new(2026, 3, 1))
    expect(months.last).to eq(Date.new(2026, 9, 1))
  end

  it "agrupa gastos do cartão por fatura e soma o total certo" do
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

  it "AC 14: faturas de dois cartões vencendo no mesmo mês aparecem juntas em due_in" do
    card_b = create_card(name: "Roxo", closing_day: 5, due_day: 12)
    credit_expense(120_000, Date.new(2026, 3, 4))
    credit_expense(80_000, Date.new(2026, 3, 4), on: card_b)
    due = Budgeting::StatementSet.due_in(month: Date.new(2026, 3, 1))
    expect(due.values.flatten.sum(&:amount_cents)).to eq(200_000)
    expect(due.keys.map { |s| s.card.id }).to contain_exactly(card.id, card_b.id)
  end
end
