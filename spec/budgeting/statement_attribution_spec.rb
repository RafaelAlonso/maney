require "rails_helper"

RSpec.describe Budgeting::StatementAttribution do
  let(:card) { create_card } # Azul: fecha 5, vence 12, vigente desde 01/01/2026

  def statement_for(date)
    described_class.statement_for(card:, date:)
  end

  it "AC 1: compra em 04/03 cai na fatura que fecha 05/03 e vence 12/03" do
    statement = statement_for(Date.new(2026, 3, 4))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 5))
    expect(statement.effective_due).to eq(Date.new(2026, 3, 12))
  end

  it "AC 2: compras no dia do fechamento (05/03) e depois (06/03) vão para a fatura seguinte" do
    [Date.new(2026, 3, 5), Date.new(2026, 3, 6)].each do |date|
      expect(statement_for(date).effective_due).to eq(Date.new(2026, 4, 13))
    end
  end

  it "AC 5: fechamento nominal 05/04 (domingo) → efetivo 03/04; compra em 03/04 vai para a seguinte, em 02/04 fica" do
    expect(statement_for(Date.new(2026, 4, 2)).effective_closing).to eq(Date.new(2026, 4, 3))
    expect(statement_for(Date.new(2026, 4, 3)).effective_closing).to eq(Date.new(2026, 5, 5))
  end

  it "AC 6: vencimento nominal 12/04 (domingo) → efetivo 13/04, orçado permanece em abril" do
    statement = statement_for(Date.new(2026, 3, 6))
    expect(statement.nominal_due).to eq(Date.new(2026, 4, 12))
    expect(statement.effective_due).to eq(Date.new(2026, 4, 13))
  end

  it "AC 7: cartão que fecha dia 30 — em fevereiro/2026 a fatura fecha 02/03/2026" do
    card30 = create_card(name: "Trinta", closing_day: 30, due_day: 10)
    statement = described_class.statement_for(card: card30, date: Date.new(2026, 2, 25))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 2))
  end

  it "AC 8: fecha 20 / vence 10 — fatura que fecha 20/03 vence 10/04" do
    card20 = create_card(name: "Verde", closing_day: 20, due_day: 10)
    statement = described_class.statement_for(card: card20, date: Date.new(2026, 3, 10))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 20))
    expect(statement.effective_due).to eq(Date.new(2026, 4, 10))
  end

  it "AC 19: mudança do fechamento de 5 para 20 preserva faturas fechadas; da aberta em diante vale o dia 20" do
    # vigência nova a partir do início da janela aberta (05/03)
    card.card_schedules.create!(closing_day: 20, due_day: 12, valid_from: Date.new(2026, 3, 5))
    expect(statement_for(Date.new(2026, 3, 4)).effective_closing).to eq(Date.new(2026, 3, 5))  # fechada, intacta
    expect(statement_for(Date.new(2026, 3, 10)).effective_closing).to eq(Date.new(2026, 3, 20)) # aberta, dia novo
    expect(statement_for(Date.new(2026, 3, 25)).effective_closing).to eq(Date.new(2026, 4, 20)) # seguinte
  end

  it "edge: novo dia de fechamento já ultrapassado no ciclo — a fatura aberta fecha imediatamente" do
    late = create_card(name: "Tarde", closing_day: 25, due_day: 5, valid_from: Date.new(2026, 1, 1))
    late.card_schedules.create!(closing_day: 5, due_day: 12, valid_from: Date.new(2026, 2, 25))
    statement = described_class.statement_for(card: late, date: Date.new(2026, 2, 26))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 5))
    expect(statement.closed?(today: Date.new(2026, 3, 10))).to be(true)
    expect(statement.open?(today: Date.new(2026, 3, 4))).to be(true)
  end

  it "identidade: mesma fatura para datas na mesma janela, faturas distintas para janelas distintas" do
    a = statement_for(Date.new(2026, 3, 1))
    b = statement_for(Date.new(2026, 3, 4))
    c = statement_for(Date.new(2026, 3, 6))
    expect(a).to eq(b)
    expect(a).not_to eq(c)
    expect([a, b, c].uniq.size).to eq(2)
  end

  it "parcelas: cada parcela cai na fatura seguinte do cartão (AC 9, sequência)" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card: card, category: category("casa")
    )
    due_dates = (1..10).map do |k|
      described_class.statement_for_installment(purchase:, number: k).effective_due
    end
    expect(due_dates.first).to eq(Date.new(2026, 4, 13))  # fatura da compra
    expect(due_dates[1]).to eq(Date.new(2026, 5, 12))     # parcela 2
    expect(due_dates.last).to eq(Date.new(2027, 1, 12))   # parcela 10 — virada de ano intacta
  end

  it "parcelas com parcela inicial: a primeira criada ancora na fatura da data (AC 11)" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10, first_installment: 4,
      date: Date.new(2026, 3, 10), card: card, category: category("casa")
    )
    expect(described_class.statement_for_installment(purchase:, number: 4).effective_due)
      .to eq(Date.new(2026, 4, 13))
    expect(described_class.statement_for_installment(purchase:, number: 5).effective_due)
      .to eq(Date.new(2026, 5, 12))
  end
end
