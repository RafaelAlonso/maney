require "rails_helper"

RSpec.describe CardSchedule do
  let(:card) { Card.create!(name: "Azul") }

  it "requires days between 1 and 31 and the validity-window start date" do
    valid = card.card_schedules.new(closing_day: 5, due_day: 12, valid_from: Date.new(2026, 1, 1))
    expect(valid).to be_valid

    expect(card.card_schedules.new(closing_day: 0, due_day: 12, valid_from: Date.new(2026, 1, 1))).not_to be_valid
    expect(card.card_schedules.new(closing_day: 5, due_day: 32, valid_from: Date.new(2026, 1, 1))).not_to be_valid
    expect(card.card_schedules.new(closing_day: 5, due_day: 12, valid_from: nil)).not_to be_valid
  end

  it "doesn't accept two validity windows of the same card starting on the same day" do
    card.card_schedules.create!(closing_day: 5, due_day: 12, valid_from: Date.new(2026, 1, 1))
    dup = card.card_schedules.new(closing_day: 20, due_day: 12, valid_from: Date.new(2026, 1, 1))
    expect(dup).not_to be_valid
  end
end
