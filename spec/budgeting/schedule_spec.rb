require "rails_helper"

RSpec.describe Budgeting::Schedule do
  it "cai para a vigência mais antiga quando a data é anterior a todas as vigências" do
    card = create_card # Azul: closing_day 5, due_day 12, vigente desde 01/01/2026
    card.card_schedules.create!(closing_day: 20, due_day: 10, valid_from: Date.new(2026, 6, 1))

    schedule = described_class.for(card:, date: Date.new(2025, 1, 1))

    expect(schedule.closing_day).to eq(5)
    expect(schedule.due_day).to eq(12)
    expect(schedule.valid_from).to eq(Date.new(2026, 1, 1))
  end

  it "levanta ArgumentError quando o cartão não tem nenhuma vigência cadastrada" do
    card = Card.create!(name: "Sem vigência")

    expect { described_class.for(card:, date: Date.new(2026, 1, 1)) }
      .to raise_error(ArgumentError, /card #{card.id} has no schedule/)
  end

  def count_card_schedule_queries
    count = 0
    callback = ->(*, payload) { count += 1 if payload[:sql].include?("card_schedules") }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  it "Fix 5(b): memoiza por (cartão, data) — chamadas repetidas não refazem a consulta" do
    card = create_card

    queries = count_card_schedule_queries do
      3.times { described_class.for(card:, date: Date.new(2026, 3, 8)) }
    end

    expect(queries).to eq(1)
  end

  it "Fix 5(b): o cache não sobrevive a uma nova vigência do mesmo cartão, mesmo dentro do exemplo" do
    card = create_card # fecha 5, vence 12, vigente desde 01/01/2026
    first = described_class.for(card:, date: Date.new(2026, 3, 8))
    expect(first.due_day).to eq(12)

    card.card_schedules.create!(closing_day: 5, due_day: 20, valid_from: Date.new(2026, 3, 1))

    second = described_class.for(card:, date: Date.new(2026, 3, 8))
    expect(second.due_day).to eq(20) # não a resposta velha, presa em cache
  end

  it "Fix 5(b): varrer todas as parcelas de uma compra 24x não paga custo quadrático em Schedule.for" do
    card = create_card
    purchase = InstallmentPurchase.create!(
      name: "eletrônico", total_cents: 240_000, installments_count: 24,
      date: Date.new(2026, 3, 10), card:, category: category("casa")
    )

    queries = count_card_schedule_queries do
      (1..24).each { |k| Budgeting::StatementAttribution.statement_for_installment(purchase:, number: k) }
    end

    # sem memoização isso é O(N²) (~300 consultas para N=24); com cache por
    # (cartão, data) fica limitado ao número de fechamentos distintos.
    expect(queries).to be <= 25
  end
end
