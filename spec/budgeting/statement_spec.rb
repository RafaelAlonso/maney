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

  it "Fix 1: duas faturas com o mesmo fechamento nominal mas vigências diferentes não são a mesma fatura" do
    card = create_card(closing_day: 5, due_day: 12, valid_from: Date.new(2026, 1, 1))
    # vigência nova entra em 10/03, estritamente dentro da janela aberta em 05/03..05/04
    card.card_schedules.create!(closing_day: 5, due_day: 1, valid_from: Date.new(2026, 3, 10))

    schedule_before = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 8))
    schedule_after = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 15))

    statement_before = described_class.new(card:, cycle: Date.new(2026, 4, 1), schedule: schedule_before)
    statement_after = described_class.new(card:, cycle: Date.new(2026, 4, 1), schedule: schedule_after)

    # Mesmo fechamento nominal — é exatamente o cenário em que a identidade
    # antiga (card, nominal_closing) colidia.
    expect(statement_before.nominal_closing).to eq(Date.new(2026, 4, 5))
    expect(statement_after.nominal_closing).to eq(Date.new(2026, 4, 5))

    # Vencimentos genuinamente diferentes, porque due_day mudou de 12 para 1.
    expect(statement_before.nominal_due).to eq(Date.new(2026, 4, 12))
    expect(statement_before.effective_due).to eq(Date.new(2026, 4, 13))
    expect(statement_after.nominal_due).to eq(Date.new(2026, 5, 1))
    expect(statement_after.effective_due).to eq(Date.new(2026, 5, 1))

    expect(statement_before).not_to eq(statement_after)
    expect(statement_before.hash).not_to eq(statement_after.hash)
    expect([statement_before, statement_after].uniq.size).to eq(2)
  end
end
