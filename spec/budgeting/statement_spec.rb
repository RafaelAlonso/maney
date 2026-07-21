require "rails_helper"

RSpec.describe Budgeting::Statement do
  it "vencimento dia 29 transborda em fevereiro/2026 (28 dias) e o efetivo avança do domingo" do
    card = create_card(closing_day: 5, due_day: 29) # due_day > closing_day: sem deslocamento de mês
    schedule = Budgeting::Schedule.for(card:, date: Date.new(2026, 2, 1))

    statement = described_class.new(card:, cycle: Date.new(2026, 2, 1), schedule:)

    # nominal_date(2026, 2, 29) transborda: fevereiro/2026 tem 28 dias -> 01/03/2026 (domingo)
    expect(statement.nominal_due).to eq(Date.new(2026, 3, 1))
    expect(statement.effective_due).to eq(Date.new(2026, 3, 2)) # domingo avança para segunda
  end
end
