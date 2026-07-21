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

  # Guarda contra reintroduzir memoização global: a consulta é sempre viva.
  it "reflete imediatamente uma vigência nova do mesmo cartão" do
    card = create_card # fecha 5, vence 12, vigente desde 01/01/2026
    first = described_class.for(card:, date: Date.new(2026, 3, 8))
    expect(first.due_day).to eq(12)

    card.card_schedules.create!(closing_day: 5, due_day: 20, valid_from: Date.new(2026, 3, 1))

    second = described_class.for(card:, date: Date.new(2026, 3, 8))
    expect(second.due_day).to eq(20) # não a resposta velha
  end
end
