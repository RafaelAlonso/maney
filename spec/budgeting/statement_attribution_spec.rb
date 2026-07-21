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

  it "regressão: transbordo de fechamento + mudança de vigência no próprio boundary — succ pega a vigência nova" do
    card30 = create_card(name: "Trinta", closing_day: 30, due_day: 10) # AC 7: fecha 30, transborda em fevereiro
    february_statement = described_class.statement_for(card: card30, date: Date.new(2026, 2, 25))
    expect(february_statement.effective_closing).to eq(Date.new(2026, 3, 2)) # transbordou para fora de fevereiro

    # vigência nova entra em vigor exatamente no boundary transbordado (AC 19: valia da janela aberta em diante)
    card30.card_schedules.create!(closing_day: 15, due_day: 10, valid_from: Date.new(2026, 3, 2))

    succeeding_statement = february_statement.succ
    # dia 15/03/2026 é domingo -> efetivo recua para sexta 13/03
    expect(succeeding_statement.effective_closing).to eq(Date.new(2026, 3, 13))
    expect(succeeding_statement).to eq(described_class.statement_for(card: card30, date: Date.new(2026, 3, 2)))

    purchase = InstallmentPurchase.create!(
      name: "presente", total_cents: 20_000, installments_count: 2,
      date: Date.new(2026, 2, 25), card: card30, category: category("casa")
    )
    expect(described_class.statement_for_installment(purchase:, number: 2).effective_closing)
      .to eq(Date.new(2026, 3, 13))
  end

  # Fronteira real de janela: a data em que a janela que contém `date` abriu.
  # É onde uma vigência nova pode entrar sem bisseccionar uma janela.
  describe ".window_start" do
    # Azul: fecha 5, vence 12, primeira vigência em 01/03/2026 (first_month).
    let(:card) do
      create_setting!(first_month: Date.new(2026, 3, 1))
      create_card!
    end
    let(:today) { Date.new(2026, 7, 21) } # terça

    def window_start(date)
      described_class.window_start(card:, date:)
    end

    # Fechamentos efetivos desta vigência (nominal dia 5, recuo no fim de semana):
    #   03: 05/03 quinta -> 05/03 | 04: 05/04 DOMINGO -> 03/04 sexta
    #   05: 05/05 terça  -> 05/05 | 06: 05/06 sexta   -> 05/06
    #   07: 05/07 DOMINGO -> 03/07 sexta | 08: 05/08 quarta -> 05/08
    it "devolve 03/07 para 21/07 — a janela aberta é [03/07, 05/08), não o mês nem hoje" do
      expect(window_start(today)).to eq(Date.new(2026, 7, 3))
      expect(window_start(today)).not_to eq(today)
      expect(window_start(today)).not_to eq(today.beginning_of_month)
    end

    it "invariante: a data devolvida é sempre o fechamento efetivo da fatura anterior" do
      {
        Date.new(2026, 4, 10) => Date.new(2026, 4, 3),  # 05/04 é domingo
        Date.new(2026, 6, 30) => Date.new(2026, 6, 5),
        Date.new(2026, 7, 21) => Date.new(2026, 7, 3)   # 05/07 é domingo
      }.each do |probe, expected|
        w = window_start(probe)
        aggregate_failures("janela de #{probe}") do
          expect(w).to eq(expected)
          expect(statement_for(w - 1).effective_closing).to eq(w),
                                                            "janela de #{probe} abriu em #{w}, que não é fechamento efetivo de fatura nenhuma"
        end
      end
    end

    it "toda data em [w, próximo fechamento) resolve para a mesma fatura" do
      w = window_start(today)

      expect(statement_for(w)).to eq(statement_for(w + 5))
      expect(statement_for(w)).to eq(statement_for(today))
      expect(statement_for(w).effective_closing).to eq(Date.new(2026, 8, 5))
      expect(statement_for(w - 1)).not_to eq(statement_for(w)) # véspera é outra janela
    end

    it "não recua além do início da linha do tempo do cartão" do
      expect(window_start(Date.new(2026, 3, 2))).to eq(Date.new(2026, 3, 1))
      expect(window_start(Date.new(2026, 3, 1))).to eq(Date.new(2026, 3, 1))
      expect(window_start(Date.new(2025, 12, 31))).to eq(Date.new(2026, 3, 1))
    end

    it "levanta ArgumentError quando o cartão não tem nenhuma vigência" do
      naked = Card.create!(name: "Sem vigência")

      expect { described_class.window_start(card: naked, date: today) }
        .to raise_error(ArgumentError, /card #{naked.id} has no schedule/)
    end
  end
end
