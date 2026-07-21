require "rails_helper"

RSpec.describe Card do
  it "exige nome" do
    expect(Card.new(name: "")).not_to be_valid
    expect(Card.new(name: "Azul")).to be_valid
  end

  describe "#reschedule" do
    include ActiveSupport::Testing::TimeHelpers

    let(:today) { Date.new(2026, 7, 21) } # terça, dentro da janela [03/07, 05/08)

    # Azul: fecha 5, vence 12, primeira vigência em 01/03/2026 (first_month).
    let(:card) do
      create_setting!(first_month: Date.new(2026, 3, 1))
      create_card!
    end

    def statement_for(date)
      Budgeting::StatementAttribution.statement_for(card:, date:)
    end

    def schedule_on(date)
      Budgeting::Schedule.for(card:, date:)
    end

    # Regra que dá sentido à tarefa: toda vigência que não seja a primeira
    # começa num fechamento efetivo real. Escrita como laço para continuar
    # valendo quando tarefas futuras acrescentarem linhas.
    def expect_every_schedule_on_a_real_boundary
      rows = card.card_schedules.reload.order(:valid_from).to_a
      rows.drop(1).each do |row|
        expect(statement_for(row.valid_from - 1).effective_closing).to eq(row.valid_from),
                                                                      "vigência de #{row.valid_from} não começa num fechamento efetivo de fatura"
      end
    end

    it "devolve nil quando os dias pedidos já são os vigentes" do
      expect(card.reschedule(closing_day: 5, due_day: 12, today:)).to be_nil
    end

    it "posiciona a vigência nova no início da janela aberta (03/07), não em hoje" do
      row = card.reschedule(closing_day: 20, due_day: 27, today:)

      expect(row.valid_from).to eq(Date.new(2026, 7, 3))
      expect(row.valid_from).not_to eq(today) # o bug que esta tarefa existe para matar
      expect(row.closing_day).to eq(20)
      expect(row.due_day).to eq(27)
    end

    it "não salva nada — quem chama valida e salva na própria transação" do
      expect(card.reschedule(closing_day: 20, due_day: 27, today:)).not_to be_persisted
      expect { card.reschedule(closing_day: 20, due_day: 27, today:) }
        .not_to change { CardSchedule.count }
    end

    # Contraponto ao exemplo acima: `persisted?` não é contrato. Com a linha do
    # tempo começando no futuro (hoje antes da primeira vigência) a fronteira é
    # a própria data inicial, então volta a linha inicial JÁ persistida, suja.
    # Quem chama salva do mesmo jeito.
    it "linha do tempo no futuro: devolve a vigência inicial já persistida, com os dias novos" do
      row = card.reschedule(closing_day: 20, due_day: 27, today: Date.new(2026, 2, 10))

      expect(row).to be_persisted
      expect(row).to eq(card.card_schedules.first)
      expect(row.valid_from).to eq(Date.new(2026, 3, 1))
      expect(row.closing_day).to eq(20)
      expect(row.due_day).to eq(27)

      row.save!
      expect(card.card_schedules.reload.count).to eq(1)
      expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(20)
    end

    it "depois de salva: vigência antiga intacta, nova em vigor da janela aberta em diante" do
      card.reschedule(closing_day: 20, due_day: 27, today:).save!

      expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)  # fatura fechada, intacta
      expect(schedule_on(today).closing_day).to eq(20)
      expect(schedule_on(today).due_day).to eq(27)
      expect(card.card_schedules.count).to eq(2)
    end

    it "duas correções no mesmo dia amendam a mesma linha em vez de empilhar outra" do
      travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
        # Dias 28/27: ainda por vir dentro da janela aberta, então a primeira
        # correção não fecha fatura nenhuma e a fronteira segue em 03/07.
        card.reschedule(closing_day: 28, due_day: 10).save!
        card.reschedule(closing_day: 27, due_day: 10).save!

        expect(card.card_schedules.reload.count).to eq(2)
        expect(card.card_schedules.maximum(:valid_from)).to eq(Date.new(2026, 7, 3))
        expect(schedule_on(Date.current).closing_day).to eq(27)
        expect(schedule_on(Date.current).due_day).to eq(10)
        expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)
      end
    end

    # Contraponto: quando a primeira correção adota um dia de fechamento que a
    # janela aberta JÁ passou, ela fecha uma fatura na hora (janela [03/07,
    # 20/07), fechada em 20/07 — ontem). A segunda correção do mesmo dia cai
    # numa janela nova e por isso empilha uma linha: amendar a de 03/07
    # reabriria uma fatura já fechada. Não amendar aqui é o comportamento
    # correto, não uma regressão de "duas correções no mesmo dia".
    it "segunda correção no mesmo dia empilha linha quando a primeira fechou uma fatura na hora" do
      travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
        card.reschedule(closing_day: 20, due_day: 27).save!
        expect(statement_for(Date.current).effective_closing).to eq(Date.new(2026, 8, 20))
        expect(statement_for(Date.new(2026, 7, 19)).closed?(today: Date.current)).to be(true)

        card.reschedule(closing_day: 21, due_day: 27).save!

        rows = card.card_schedules.reload.order(:valid_from).map { [_1.valid_from, _1.closing_day, _1.due_day] }
        expect(rows).to eq([
                             [Date.new(2026, 3, 1), 5, 12],
                             [Date.new(2026, 7, 3), 20, 27],
                             [Date.new(2026, 7, 20), 21, 27]
                           ])
        expect(schedule_on(Date.current).closing_day).to eq(21)
        expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)
        expect_every_schedule_on_a_real_boundary
      end
    end

    # Cartão que fecha 31: em fevereiro/2026 o fechamento transborda para
    # 03/03 (terça). A primeira edição nasce nessa fronteira com o dia 1, e aí
    # succ passa a resolver a vigência EM 03/03 — o ciclo 03 fecha nominalmente
    # em 01/03 (domingo), efetivo 27/02. A cadeia RECUA, e a fronteira
    # calculada anteciparia uma vigência que já existe.
    context "quando a troca de vigência faz a cadeia de faturas recuar" do
      let(:card) { create_card(name: "Trinta e um", closing_day: 31, due_day: 10, valid_from: Date.new(2026, 1, 1)) }

      it "nunca posiciona a vigência nova antes de uma já existente" do
        card.reschedule(closing_day: 1, due_day: 10, today: Date.new(2026, 3, 10)).save!
        expect(card.card_schedules.reload.maximum(:valid_from)).to eq(Date.new(2026, 3, 3))

        row = card.reschedule(closing_day: 15, due_day: 20, today: Date.new(2026, 3, 20))

        expect(row.valid_from).to be >= card.card_schedules.maximum(:valid_from),
                                  "vigência nova em #{row.valid_from} antecede a vigência existente de #{card.card_schedules.maximum(:valid_from)}"
        expect(row.valid_from).to eq(Date.new(2026, 3, 3)) # amenda a linha da fronteira, não empilha outra
        row.save!

        expect(card.card_schedules.reload.count).to eq(2)
        expect_every_schedule_on_a_real_boundary
      end

      # Meses depois, a fronteira da janela aberta já saiu de 03/03 há muito.
      # Uma travessia com succ, porém, para no mergulho de março e devolve
      # 03/03 para sempre: a edição de junho reescreveria a linha do meio,
      # apagando uma vigência e reatribuindo três faturas já fechadas.
      it "edição meses depois abre vigência nova na janela aberta, sem reescrever a do meio" do
        card.reschedule(closing_day: 1, due_day: 10, today: Date.new(2026, 3, 10)).save!
        expect(card.card_schedules.reload.maximum(:valid_from)).to eq(Date.new(2026, 3, 3))

        row = card.reschedule(closing_day: 15, due_day: 20, today: Date.new(2026, 6, 15))

        expect(row.valid_from).to eq(Date.new(2026, 6, 1)),
                                  "vigência nova em #{row.valid_from}: retroagiu por cima de faturas já fechadas"
        row.save!

        rows = card.card_schedules.reload.order(:valid_from).map { [_1.valid_from, _1.closing_day, _1.due_day] }
        expect(rows).to eq([
                             [Date.new(2026, 1, 1), 31, 10],
                             [Date.new(2026, 3, 3), 1, 10],
                             [Date.new(2026, 6, 1), 15, 20]
                           ])
        expect_every_schedule_on_a_real_boundary
      end
    end

    it "invariante: toda vigência posterior à primeira começa num fechamento efetivo real" do
      expect_every_schedule_on_a_real_boundary # linha única: nada a checar, mas o laço roda

      card.reschedule(closing_day: 20, due_day: 27, today:).save!

      expect(card.card_schedules.count).to eq(2)
      expect_every_schedule_on_a_real_boundary
    end
  end
end
