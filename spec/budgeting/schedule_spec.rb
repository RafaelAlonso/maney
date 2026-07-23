require "rails_helper"

RSpec.describe Budgeting::Schedule do
  it "falls back to the oldest validity window when the date precedes all of them" do
    card = create_card # Azul: closing_day 5, due_day 12, in effect since 01/01/2026
    card.card_schedules.create!(closing_day: 20, due_day: 10, valid_from: Date.new(2026, 6, 1))

    schedule = described_class.for(card:, date: Date.new(2025, 1, 1))

    expect(schedule.closing_day).to eq(5)
    expect(schedule.due_day).to eq(12)
    expect(schedule.valid_from).to eq(Date.new(2026, 1, 1))
  end

  it "raises ArgumentError when the card has no validity window registered" do
    card = Card.create!(name: "Sem vigência")

    expect { described_class.for(card:, date: Date.new(2026, 1, 1)) }
      .to raise_error(ArgumentError, /card #{card.id} has no schedule/)
  end

  # Guards against reintroducing global memoization: the query is always live.
  it "immediately reflects a new validity window on the same card" do
    card = create_card # closes 5, due 12, in effect since 01/01/2026
    first = described_class.for(card:, date: Date.new(2026, 3, 8))
    expect(first.due_day).to eq(12)

    card.card_schedules.create!(closing_day: 5, due_day: 20, valid_from: Date.new(2026, 3, 1))

    second = described_class.for(card:, date: Date.new(2026, 3, 8))
    expect(second.due_day).to eq(20) # not the stale answer
  end
end
