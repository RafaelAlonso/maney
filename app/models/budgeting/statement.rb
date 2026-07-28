module Budgeting
  # Derived statement — never persisted. Natural identity:
  # (card, nominal closing date, nominal due date) — the due date is included
  # because it comes from the schedule (validity window) in effect, which can
  # diverge between two statements with the same nominal closing.
  class Statement
    attr_reader :card, :cycle, :schedule

    # `memo:` is an optional Budgeting::ScheduleMemo, carried only so that `succ`
    # can resolve the next window without a query. It is not part of the
    # identity: two statements are equal regardless of how they were derived.
    def initialize(card:, cycle:, schedule:, memo: nil)
      @card = card
      @cycle = cycle.beginning_of_month
      @schedule = schedule
      @memo = memo
    end

    def nominal_closing = Calendar.nominal_date(cycle.year, cycle.month, schedule.closing_day)
    def effective_closing = Calendar.effective_closing(nominal_closing)

    # A due date earlier than the closing => it's due in the month after the cycle's.
    def nominal_due
      base = schedule.due_day < schedule.closing_day ? cycle >> 1 : cycle
      Calendar.nominal_date(base.year, base.month, schedule.due_day)
    end

    def effective_due = Calendar.effective_due(nominal_due)

    # URL id: readable, stable across deep links, and part of the natural
    # identity. Resolved back through Budgeting::CardStatements#find.
    def to_param = nominal_closing.to_s

    def closed?(today:) = effective_closing <= today
    def open?(today:) = !closed?(today:)

    def succ
      next_cycle = cycle >> 1
      # Window N+1 opens exactly when window N closes, so the validity window in
      # effect for it is the one valid at that closing — not the 1st of the
      # calendar month, which a closing-day overflow can precede.
      Statement.new(card:, cycle: next_cycle, memo: @memo,
                    schedule: Schedule.for(card:, date: effective_closing, memo: @memo))
    end

    def ==(other)
      other.is_a?(Statement) && other.card.id == card.id &&
        other.nominal_closing == nominal_closing && other.nominal_due == nominal_due
    end
    alias eql? ==

    def hash = [card.id, nominal_closing, nominal_due].hash
  end
end
