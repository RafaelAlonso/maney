require "rails_helper"

RSpec.describe Budgeting::MonthSummary do
  let(:march) { Date.new(2026, 3, 1) }
  let(:card) { create_card }
  let(:mercado) { category("mercado") }

  before { Setting.create!(first_month: march, initial_balance_cents: 0) }

  def summary(month = march) = described_class.new(month:, today: Date.new(2026, 3, 15))

  def debit(amount, date, cat:, name: "gasto")
    Expense.create!(name:, amount_cents: amount, date:, payment_method: "debit", category: cat)
  end

  def credit(amount, date, cat: mercado)
    Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                    card:, category: cat)
  end

  it "AC 3: compra no crédito consome a categoria no mês da compra e o orçado cartão de crédito no mês do vencimento — sem tocar o saldo atual" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    credit(20_000, Date.new(2026, 3, 4))
    expect(summary.spent_cents(mercado)).to eq(20_000)
    expect(summary.budgeted_cents(credit_card_category)).to eq(20_000) # fatura vence 12/03
    expect(summary(Date.new(2026, 4, 1)).spent_cents(mercado)).to eq(0) # não debita de novo
    expect(summary.current_balance_cents).to eq(500_000)
  end

  it "AC 4: compra em 05/03 consome março, mas o orçado cartão de crédito conta só em abril" do
    credit(30_000, Date.new(2026, 3, 5))
    expect(summary.spent_cents(mercado)).to eq(30_000)
    expect(summary.budgeted_cents(credit_card_category)).to eq(0)
    expect(summary(Date.new(2026, 4, 1)).budgeted_cents(credit_card_category)).to eq(30_000)
  end

  it "AC 12: ganhos 5.000, orçado 4.000, nenhuma fatura no mês → estimativa 1.000" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 250_000)
    Budget.create!(category: category("casa"), month: march, amount_cents: 150_000)
    expect(summary.estimated_balance_cents).to eq(100_000)
  end

  it "AC 13: orçado 900 e consumo 1.500 → a estimativa usa max(orçado, consumo)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 90_000)
    debit(150_000, Date.new(2026, 3, 10), cat: mercado)
    expect(summary.estimated_balance_cents).to eq(500_000 - 150_000)
  end

  it "AC 14: faturas de dois cartões (1.200 + 800) vencendo em março → orçado cartão de crédito 2.000, dentro do estimado" do
    card_b = create_card(name: "Roxo", closing_day: 5, due_day: 12)
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    credit(120_000, Date.new(2026, 3, 4))
    Expense.create!(name: "compra", amount_cents: 80_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card: card_b, category: category("casa"))
    expect(summary.budgeted_cents(credit_card_category)).to eq(200_000)
    # estimado = 5.000 − (max por categoria): mercado 1.200 + casa 800 + cartão 2.000... o
    # consumo de mercado/casa é por competência e o orçado deles é zero — max = consumo.
    expect(summary.estimated_balance_cents).to eq(500_000 - 120_000 - 80_000 - 200_000)
  end

  it "AC 15: crédito nunca toca o saldo atual; pagar fatura é gasto no débito na categoria cartão de crédito" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    debit(100_000, Date.new(2026, 3, 8), cat: mercado)
    credit(120_000, Date.new(2026, 3, 4)) # fatura fecha 05/03, vence 12/03 (março)
    credit(80_000, Date.new(2026, 3, 6))  # fatura vence 13/04
    expect(summary.current_balance_cents).to eq(400_000)

    debit(120_000, Date.new(2026, 3, 12), cat: credit_card_category, name: "fatura azul")
    expect(summary.current_balance_cents).to eq(280_000)
    expect(summary.spent_cents(credit_card_category)).to eq(120_000)
  end

  it "AC 18: mês sem nenhum gasto — consumo zero em todas as categorias e estimativa = ganhos − orçado, sem erro" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 90_000)
    expect(summary.spent_cents(mercado)).to eq(0)
    expect(summary.spent_cents(credit_card_category)).to eq(0)
    expect(summary.estimated_balance_cents).to eq(410_000)
  end

  it "AC 16/17: o carregado entra como primeiro ganho do mês" do
    Setting.instance.update!(initial_balance_cents: 200_000)
    expect(summary.carried_balance_cents).to eq(200_000)
    expect(summary.incomes_total_cents).to eq(200_000)
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    expect(summary.incomes_total_cents).to eq(700_000)
  end

  it "parcelas consomem seus meses: sofá 10x de março consome 100 em março e 100 em dezembro" do
    InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )
    expect(summary.spent_cents(category("casa"))).to eq(10_000)
    expect(summary(Date.new(2026, 12, 1)).spent_cents(category("casa"))).to eq(10_000)
    expect(summary(Date.new(2027, 1, 1)).spent_cents(category("casa"))).to eq(0)
  end
end
