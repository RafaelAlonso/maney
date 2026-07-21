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

    it "depois de salva: vigência antiga intacta, nova em vigor da janela aberta em diante" do
      card.reschedule(closing_day: 20, due_day: 27, today:).save!

      expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)  # fatura fechada, intacta
      expect(schedule_on(today).closing_day).to eq(20)
      expect(schedule_on(today).due_day).to eq(27)
      expect(card.card_schedules.count).to eq(2)
    end

    it "duas correções no mesmo dia amendam a mesma linha em vez de empilhar outra" do
      travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
        card.reschedule(closing_day: 20, due_day: 27).save!
        card.reschedule(closing_day: 21, due_day: 27).save!

        expect(card.card_schedules.reload.count).to eq(2)
        expect(schedule_on(Date.current).closing_day).to eq(21)
        expect(schedule_on(Date.current).due_day).to eq(27)
        expect(schedule_on(Date.new(2026, 3, 10)).closing_day).to eq(5)
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
