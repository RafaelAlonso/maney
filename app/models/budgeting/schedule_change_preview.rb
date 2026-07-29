module Budgeting
  # What a pending card-days change does to the statements the user still has in
  # front of them. Read-only and derived from the proposed days alone — nothing
  # is written, so the card screen can show this *before* the change is saved.
  #
  # Why it exists: closing and due days are independent here, so a correction can
  # flip `due_day < closing_day` and, with it, the "due in the month after the
  # cycle" rule (see Statement#nominal_due). That inserts a one-time month-long
  # gap in the card's statement chain — every statement from the open one onward
  # is due a month later, and a running installment plan travels with them (one
  # installment per statement, as always). The engine is right to do that; what
  # was missing is that the user had no way to see it coming. Changing the days
  # from 5/12 to 20/12 read as a small correction and silently postponed six
  # remaining installments by a month.
  class ScheduleChangePreview
    Row = Data.define(:cycle, :before_due, :after_due) do
      def shifts? = before_due != after_due
    end

    # The open statement plus the two after it — far enough to show the gap and
    # that the chain settles back into a monthly rhythm afterwards.
    CYCLES = 3

    def initialize(card:, proposed:, today: Date.current)
      @card = card
      @proposed = proposed
      @today = today
      @memo = ScheduleMemo.new
    end

    def rows
      @rows ||= begin
        current = Schedule.for(card: @card, date: @today, memo: @memo)
        first_cycle = StatementAttribution.statement_for(card: @card, date: @today, memo: @memo).cycle
        Array.new(CYCLES) do |index|
          cycle = first_cycle >> index
          Row.new(cycle:,
                  before_due: due_for(cycle, current),
                  after_due: due_for(cycle, @proposed))
        end
      end
    end

    def shifts? = rows.any?(&:shifts?)

    # Installments already entered that no statement has billed yet — the ones a
    # shift actually postpones. Counted through the same attribution the screens
    # use, so it can't disagree with them.
    def unbilled_installments
      @unbilled_installments ||=
        @card.expenses.where.not(installment_purchase_id: nil).includes(:installment_purchase)
             .count { |expense| StatementSet.statement_of(expense, memo: @memo).open?(today: @today) }
    end

    private

    def due_for(cycle, schedule)
      Statement.new(card: @card, cycle:, schedule:).effective_due
    end
  end
end
