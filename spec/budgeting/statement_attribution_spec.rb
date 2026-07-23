require "rails_helper"

RSpec.describe Budgeting::StatementAttribution do
  let(:card) { create_card } # Azul: closes 5, due 12, in effect since 01/01/2026

  def statement_for(date)
    described_class.statement_for(card:, date:)
  end

  it "AC 1: a purchase on 04/03 lands on the statement that closes 05/03 and is due 12/03" do
    statement = statement_for(Date.new(2026, 3, 4))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 5))
    expect(statement.effective_due).to eq(Date.new(2026, 3, 12))
  end

  it "AC 2: purchases on the closing day (05/03) and after (06/03) go to the next statement" do
    [Date.new(2026, 3, 5), Date.new(2026, 3, 6)].each do |date|
      expect(statement_for(date).effective_due).to eq(Date.new(2026, 4, 13))
    end
  end

  it "AC 5: nominal closing 05/04 (Sunday) → effective 03/04; a purchase on 03/04 goes to the next, on 02/04 stays" do
    expect(statement_for(Date.new(2026, 4, 2)).effective_closing).to eq(Date.new(2026, 4, 3))
    expect(statement_for(Date.new(2026, 4, 3)).effective_closing).to eq(Date.new(2026, 5, 5))
  end

  it "AC 6: nominal due 12/04 (Sunday) → effective 13/04, budgeted stays in April" do
    statement = statement_for(Date.new(2026, 3, 6))
    expect(statement.nominal_due).to eq(Date.new(2026, 4, 12))
    expect(statement.effective_due).to eq(Date.new(2026, 4, 13))
  end

  it "AC 7: a card that closes on day 30 — in February/2026 the statement closes 02/03/2026" do
    card30 = create_card(name: "Trinta", closing_day: 30, due_day: 10)
    statement = described_class.statement_for(card: card30, date: Date.new(2026, 2, 25))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 2))
  end

  it "AC 8: closes 20 / due 10 — a statement closing 20/03 is due 10/04" do
    card20 = create_card(name: "Verde", closing_day: 20, due_day: 10)
    statement = described_class.statement_for(card: card20, date: Date.new(2026, 3, 10))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 20))
    expect(statement.effective_due).to eq(Date.new(2026, 4, 10))
  end

  it "AC 19: changing the closing from 5 to 20 preserves closed statements; from the open one on, day 20 applies" do
    # new validity window from the start of the open window (05/03)
    card.card_schedules.create!(closing_day: 20, due_day: 12, valid_from: Date.new(2026, 3, 5))
    expect(statement_for(Date.new(2026, 3, 4)).effective_closing).to eq(Date.new(2026, 3, 5))  # closed, intact
    expect(statement_for(Date.new(2026, 3, 10)).effective_closing).to eq(Date.new(2026, 3, 20)) # open, new day
    expect(statement_for(Date.new(2026, 3, 25)).effective_closing).to eq(Date.new(2026, 4, 20)) # next
  end

  it "edge: a new closing day already passed in the cycle — the open statement closes immediately" do
    late = create_card(name: "Tarde", closing_day: 25, due_day: 5, valid_from: Date.new(2026, 1, 1))
    late.card_schedules.create!(closing_day: 5, due_day: 12, valid_from: Date.new(2026, 2, 25))
    statement = described_class.statement_for(card: late, date: Date.new(2026, 2, 26))
    expect(statement.effective_closing).to eq(Date.new(2026, 3, 5))
    expect(statement.closed?(today: Date.new(2026, 3, 10))).to be(true)
    expect(statement.open?(today: Date.new(2026, 3, 4))).to be(true)
  end

  it "identity: same statement for dates in the same window, distinct statements for distinct windows" do
    a = statement_for(Date.new(2026, 3, 1))
    b = statement_for(Date.new(2026, 3, 4))
    c = statement_for(Date.new(2026, 3, 6))
    expect(a).to eq(b)
    expect(a).not_to eq(c)
    expect([a, b, c].uniq.size).to eq(2)
  end

  it "installments: each installment lands on the card's next statement (AC 9, sequence)" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card: card, category: category("casa")
    )
    due_dates = (1..10).map do |k|
      described_class.statement_for_installment(purchase:, number: k).effective_due
    end
    expect(due_dates.first).to eq(Date.new(2026, 4, 13))  # the purchase's statement
    expect(due_dates[1]).to eq(Date.new(2026, 5, 12))     # installment 2
    expect(due_dates.last).to eq(Date.new(2027, 1, 12))   # installment 10 — year rollover intact
  end

  it "installments with a first installment: the first created anchors on the date's statement (AC 11)" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10, first_installment: 4,
      date: Date.new(2026, 3, 10), card: card, category: category("casa")
    )
    expect(described_class.statement_for_installment(purchase:, number: 4).effective_due)
      .to eq(Date.new(2026, 4, 13))
    expect(described_class.statement_for_installment(purchase:, number: 5).effective_due)
      .to eq(Date.new(2026, 5, 12))
  end

  it "regression: closing overflow + validity-window change on the boundary itself — succ picks up the new window" do
    card30 = create_card(name: "Trinta", closing_day: 30, due_day: 10) # AC 7: closes 30, overflows in February
    february_statement = described_class.statement_for(card: card30, date: Date.new(2026, 2, 25))
    expect(february_statement.effective_closing).to eq(Date.new(2026, 3, 2)) # overflowed out of February

    # new validity window takes effect exactly on the overflowed boundary (AC 19: valid from the open window on)
    card30.card_schedules.create!(closing_day: 15, due_day: 10, valid_from: Date.new(2026, 3, 2))

    succeeding_statement = february_statement.succ
    # 15/03/2026 is a Sunday -> effective moves back to Friday 13/03
    expect(succeeding_statement.effective_closing).to eq(Date.new(2026, 3, 13))
    expect(succeeding_statement).to eq(described_class.statement_for(card: card30, date: Date.new(2026, 3, 2)))

    purchase = InstallmentPurchase.create!(
      name: "presente", total_cents: 20_000, installments_count: 2,
      date: Date.new(2026, 2, 25), card: card30, category: category("casa")
    )
    expect(described_class.statement_for_installment(purchase:, number: 2).effective_closing)
      .to eq(Date.new(2026, 3, 13))
  end

  # Real window boundary: the date on which the window containing `date` opened.
  # It's where a new validity window can start without bisecting a window.
  describe ".window_start" do
    # Azul: closes 5, due 12, first validity window on 01/03/2026 (first_month).
    let(:card) do
      create_setting!(first_month: Date.new(2026, 3, 1))
      create_card!
    end
    let(:today) { Date.new(2026, 7, 21) } # Tuesday

    def window_start(date)
      described_class.window_start(card:, date:)
    end

    # The property that gives window_start meaning, without relying on
    # hand-picked dates: w is the SMALLEST day that still falls in `date`'s
    # statement. If the day before w fell in the same statement, the boundary
    # would have moved back into already-closed statements — exactly how a days
    # edit becomes retroactive. Holds for any card; use it on every new fixture.
    def expect_window_start_to_bound_the_statement(subject_card, date)
      w = described_class.window_start(card: subject_card, date:)
      earliest = subject_card.card_schedules.minimum(:valid_from)
      today_statement = described_class.statement_for(card: subject_card, date:)

      aggregate_failures("window of #{date} on card #{subject_card.name}") do
        expect(w).to be <= date, "window of #{date} started after it, at #{w}"
        expect(described_class.statement_for(card: subject_card, date: w)).to eq(today_statement),
                                                                             "#{w} doesn't fall in the same statement as #{date}"
        if w > earliest
          expect(described_class.statement_for(card: subject_card, date: w - 1)).not_to eq(today_statement),
                                                                                     "#{w - 1} still falls in #{date}'s statement: the boundary moved back into already-closed statements"
        end
      end
    end

    # Effective closings of this validity window (nominal day 5, weekend move-back):
    #   03: 05/03 Thu -> 05/03 | 04: 05/04 SUNDAY -> 03/04 Fri
    #   05: 05/05 Tue -> 05/05 | 06: 05/06 Fri -> 05/06
    #   07: 05/07 SUNDAY -> 03/07 Fri | 08: 05/08 Wed -> 05/08
    it "returns 03/07 for 21/07 — the open window is [03/07, 05/08), not the month nor today" do
      expect(window_start(today)).to eq(Date.new(2026, 7, 3))
      expect(window_start(today)).not_to eq(today)
      expect(window_start(today)).not_to eq(today.beginning_of_month)
    end

    it "invariant: the returned date is always the previous statement's effective closing" do
      {
        Date.new(2026, 4, 10) => Date.new(2026, 4, 3),  # 05/04 is a Sunday
        Date.new(2026, 6, 30) => Date.new(2026, 6, 5),
        Date.new(2026, 7, 21) => Date.new(2026, 7, 3)   # 05/07 is a Sunday
      }.each do |probe, expected|
        w = window_start(probe)
        aggregate_failures("window of #{probe}") do
          expect(w).to eq(expected)
          expect(statement_for(w - 1).effective_closing).to eq(w),
                                                            "window of #{probe} opened at #{w}, which is no statement's effective closing"
        end
      end
    end

    it "every date in [w, next closing) resolves to the same statement" do
      w = window_start(today)

      expect(statement_for(w)).to eq(statement_for(w + 5))
      expect(statement_for(w)).to eq(statement_for(today))
      expect(statement_for(w).effective_closing).to eq(Date.new(2026, 8, 5))
      expect(statement_for(w - 1)).not_to eq(statement_for(w)) # the day before is another window
    end

    it "doesn't move back past the start of the card's timeline" do
      expect(window_start(Date.new(2026, 3, 2))).to eq(Date.new(2026, 3, 1))
      expect(window_start(Date.new(2026, 3, 1))).to eq(Date.new(2026, 3, 1))
      expect(window_start(Date.new(2025, 12, 31))).to eq(Date.new(2026, 3, 1))
    end

    # Regression of the bug that motivated the third attempt at this function:
    # closing on day 28 then on day 1 makes the next cycle close BEFORE the
    # boundary that opened it (01/03 is a Sunday -> effective 27/02). Any
    # traversal with succ dives in there and stops, returning a boundary months
    # back — the days edit would become retroactive over paid statements.
    context "when the validity-window swap makes the statement chain move backward" do
      let(:card) do
        create_card(name: "Vira-mês", closing_day: 28, due_day: 15, valid_from: Date.new(2026, 1, 1)).tap do |c|
          c.card_schedules.create!(closing_day: 1, due_day: 20, valid_from: Date.new(2026, 2, 27))
        end
      end

      it "returns the current window's boundary, not the date where the chain dived in" do
        aggregate_failures do
          {
            Date.new(2026, 4, 5) => Date.new(2026, 4, 1),
            Date.new(2026, 5, 10) => Date.new(2026, 5, 1),
            Date.new(2026, 6, 20) => Date.new(2026, 6, 1),
            Date.new(2026, 12, 20) => Date.new(2026, 12, 1)
          }.each do |probe, expected|
            expect(window_start(probe)).to eq(expected),
                                           "window of #{probe} started at #{window_start(probe)}, expected #{expected}"
          end
        end
      end

      it "property: the boundary bounds the statement in each month of the new validity window" do
        [Date.new(2026, 4, 5), Date.new(2026, 5, 10), Date.new(2026, 6, 20), Date.new(2026, 12, 20)].each do |probe|
          expect_window_start_to_bound_the_statement(card, probe)
        end
      end
    end

    describe "non-retroactivity property" do
      it "reference card: the boundary bounds today's statement" do
        expect_window_start_to_bound_the_statement(card, today)
        expect_window_start_to_bound_the_statement(card, Date.new(2026, 4, 10))
        expect_window_start_to_bound_the_statement(card, Date.new(2026, 3, 2))
      end

      it "a card that closes 31, after an edit: the boundary bounds today's statement" do
        card31 = create_card(name: "Trinta e um", closing_day: 31, due_day: 10, valid_from: Date.new(2026, 1, 1))
        card31.reschedule(closing_day: 1, due_day: 10, today: Date.new(2026, 3, 10)).save!

        [Date.new(2026, 3, 20), Date.new(2026, 6, 15), Date.new(2026, 9, 8)].each do |probe|
          expect_window_start_to_bound_the_statement(card31, probe)
        end
      end
    end

    it "raises ArgumentError when the card has no validity window" do
      naked = Card.create!(name: "Sem vigência")

      expect { described_class.window_start(card: naked, date: today) }
        .to raise_error(ArgumentError, /card #{naked.id} has no schedule/)
    end
  end
end
