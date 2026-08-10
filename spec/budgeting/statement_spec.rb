require "rails_helper"

RSpec.describe Budgeting::Statement do
  it "due day 29 overflows in February/2026 (28 days) and the effective date moves off Sunday" do
    card = create_card(closing_day: 5, due_day: 29) # due_day > closing_day: no month shift
    schedule = Budgeting::Schedule.for(card:, date: Date.new(2026, 2, 1))

    statement = described_class.new(card:, cycle: Date.new(2026, 2, 1), schedule:)

    # nominal_date(2026, 2, 29) overflows: February/2026 has 28 days -> 01/03/2026 (Sunday)
    expect(statement.nominal_due).to eq(Date.new(2026, 3, 1))
    expect(statement.effective_due).to eq(Date.new(2026, 3, 2)) # Sunday moves to Monday
  end

  it "Fix 1: two statements with the same nominal closing but different validity windows aren't the same statement" do
    card = create_card(closing_day: 5, due_day: 12, valid_from: Date.new(2026, 1, 1))
    # new validity window starts 10/03, strictly within the window open on 05/03..05/04
    card.card_schedules.create!(closing_day: 5, due_day: 1, valid_from: Date.new(2026, 3, 10))

    schedule_before = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 8))
    schedule_after = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 15))

    statement_before = described_class.new(card:, cycle: Date.new(2026, 4, 1), schedule: schedule_before)
    statement_after = described_class.new(card:, cycle: Date.new(2026, 4, 1), schedule: schedule_after)

    # Same nominal closing — exactly the scenario where the old identity
    # (card, nominal_closing) collided.
    expect(statement_before.nominal_closing).to eq(Date.new(2026, 4, 5))
    expect(statement_after.nominal_closing).to eq(Date.new(2026, 4, 5))

    # Genuinely different due dates, because due_day changed from 12 to 1.
    expect(statement_before.nominal_due).to eq(Date.new(2026, 4, 12))
    expect(statement_before.effective_due).to eq(Date.new(2026, 4, 13))
    expect(statement_after.nominal_due).to eq(Date.new(2026, 5, 1))
    expect(statement_after.effective_due).to eq(Date.new(2026, 5, 1))

    expect(statement_before).not_to eq(statement_after)
    expect(statement_before.hash).not_to eq(statement_after.hash)
    expect([ statement_before, statement_after ].uniq.size).to eq(2)
  end
end
