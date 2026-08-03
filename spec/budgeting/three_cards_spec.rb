require "rails_helper"

# ACs 4, 5 and 6 of "what each card owes this month". No new production code —
# the engine is already card-agnostic — but the epic's risk is silent
# misattribution: a purchase on the wrong card's statement still renders a
# plausible screen. So every total here is a literal, hand-computed constant.
# Never replace one with a sum recomputed from the derivation under test; that
# test would agree with the bug.
#
# Three cards, one validity window each from 01/03/2026, and the March cycle
# each one's own closing day dictates:
#   Azul  closes  3 -> 03/03 (Tue),               due 10 -> 10/03 (Tue)
#   Roxo  closes  8 -> Sunday, back to 06/03,     due 15 -> Sunday, forward to 16/03
#   Verde closes 15 -> Sunday, back to 13/03,     due 25 -> 25/03 (Wed)
RSpec.describe "Three cards on three closing days" do
  let(:mercado) { category("mercado") }
  let(:azul) { create_card!(name: "Azul", closing_day: 3, due_day: 10) }
  let(:roxo) { create_card!(name: "Roxo", closing_day: 8, due_day: 15) }
  let(:verde) { create_card!(name: "Verde", closing_day: 15, due_day: 25) }

  before do
    create_setting!(first_month: Date.new(2026, 3, 1))
    create_reserved_categories!
  end

  # A purchase on the same day on all three cards, and a 3x installment purchase
  # on each. Amounts chosen so every card's contribution is distinguishable in
  # any total it appears in.
  def three_cards_scenario
    { azul => [ 30_000, 90_000 ], roxo => [ 20_000, 60_000 ], verde => [ 10_000, 30_000 ] }
      .each do |card, (purchase_cents, installment_total)|
        Expense.create!(name: "compra", amount_cents: purchase_cents, date: Date.new(2026, 3, 5),
                        payment_method: "credit", card:, category: mercado)
        InstallmentPurchase.create!(name: "parcelado", total_cents: installment_total,
                                    installments_count: 3, date: Date.new(2026, 3, 20),
                                    card:, category: mercado)
      end
  end

  def rows_for(month)
    Budgeting::StatementsDue.new(month:).rows
      .map { |row| [ row.statement.card.name, row.statement.effective_due, row.amount_cents ] }
  end

  it "places the same-day purchase on the statement each card's own closing day dictates (AC 4)" do
    three_cards_scenario

    # Azul's March statement had already closed on 03/03, so its 05/03 purchase
    # falls due in April; Roxo's and Verde's had not, so theirs fall due in March.
    expect(rows_for(Date.new(2026, 3, 1))).to eq [
      [ "Roxo", Date.new(2026, 3, 16), 20_000 ],
      [ "Verde", Date.new(2026, 3, 25), 10_000 ]
    ]
    expect(rows_for(Date.new(2026, 4, 1)).map { |name, _due, cents| [ name, cents ] })
      .to include([ "Azul", 60_000 ]) # 30.000 purchase + 30.000 installment 1
  end

  it "carries only each card's own installment on its own line (AC 5)" do
    three_cards_scenario

    expect(rows_for(Date.new(2026, 5, 1))).to eq [
      [ "Azul", Date.new(2026, 5, 11), 30_000 ],
      [ "Roxo", Date.new(2026, 5, 15), 20_000 ],
      [ "Verde", Date.new(2026, 5, 25), 10_000 ]
    ]
    expect(rows_for(Date.new(2026, 6, 1))).to eq [
      [ "Azul", Date.new(2026, 6, 10), 30_000 ],
      [ "Roxo", Date.new(2026, 6, 15), 20_000 ],
      [ "Verde", Date.new(2026, 6, 25), 10_000 ]
    ]
  end

  it "totals each month to the hand-added sum of the three cards' statements (AC 6)" do
    three_cards_scenario

    expect(Budgeting::MonthSummary.new(month: Date.new(2026, 3, 1)).statements_due_cents).to eq 30_000
    expect(Budgeting::MonthSummary.new(month: Date.new(2026, 4, 1)).statements_due_cents).to eq 90_000
    expect(Budgeting::MonthSummary.new(month: Date.new(2026, 5, 1)).statements_due_cents).to eq 60_000
    expect(Budgeting::MonthSummary.new(month: Date.new(2026, 6, 1)).statements_due_cents).to eq 60_000
  end

  it "forecasts the balance against the hand-added card total (AC 6)" do
    three_cards_scenario
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 2))
    Budget.create!(category: mercado, month: Date.new(2026, 3, 1), amount_cents: 100_000)
    Budget.create!(category: mercado, month: Date.new(2026, 4, 1), amount_cents: 100_000)

    # March: 5.000 income, nothing carried. mercado's 1.000 budget is entirely
    # eaten by 1.200 of credit spending (600 of purchases + 600 of installment 1),
    # so it commits nothing in cash; the cards commit the 300 due in March.
    expect(Budgeting::MonthSummary.new(month: Date.new(2026, 3, 1)).estimated_balance_cents)
      .to eq 470_000

    # April: 5.000 carried, no income. mercado spends 600 on credit (installment 2)
    # against a 1.000 budget, leaving 400 assumed to leave as cash; the cards
    # commit the 900 due in April.
    expect(Budgeting::MonthSummary.new(month: Date.new(2026, 4, 1)).estimated_balance_cents)
      .to eq 370_000
  end

  it "reports the committed debt month by month over the three cards (AC 6)" do
    three_cards_scenario
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 2))

    solvency = Budgeting::Solvency.new(today: Date.new(2026, 3, 16))

    expect(solvency.arrears_cents).to eq 0 # March is the current month; nothing is past
    expect(solvency.rows.map { |row| [ row.month, row.committed_cents, row.cumulative_cents ] }).to eq [
      [ Date.new(2026, 3, 1), 30_000, 30_000 ],
      [ Date.new(2026, 4, 1), 90_000, 120_000 ],
      [ Date.new(2026, 5, 1), 60_000, 180_000 ],
      [ Date.new(2026, 6, 1), 60_000, 240_000 ]
    ]
    expect(solvency.money_on_hand_cents).to eq 500_000
    expect(solvency).to be_covered # 2.400 of debt against 5.000 on hand
  end
end
