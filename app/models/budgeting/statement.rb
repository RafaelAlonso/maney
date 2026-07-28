module Budgeting
  # Derived statement — never persisted. Natural identity:
  # (card, nominal closing date, nominal due date) — the due date is included
  # because it comes from the schedule (validity window) in effect, which can
  # diverge between two statements with the same nominal closing.
  class Statement
    attr_reader :card, :cycle, :schedule

    def initialize(card:, cycle:, schedule:)
      @card = card
      @cycle = cycle.beginning_of_month
      @schedule = schedule
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

    # `memo:` is an optional Budgeting::ScheduleMemo, passed through only for
    # this call's Schedule.for lookup — Statement never holds onto it.
    def succ(memo: nil)
      next_cycle = cycle >> 1
      # Window N+1 opens exactly when window N closes, so the validity window in
      # effect for it is the one valid at that closing — not the 1st of the
      # calendar month, which a closing-day overflow can precede.
      Statement.new(card:, cycle: next_cycle,
                    schedule: Schedule.for(card:, date: effective_closing, memo:))
    end

    def ==(other)
      other.is_a?(Statement) && other.card.id == card.id &&
        other.nominal_closing == nominal_closing && other.nominal_due == nominal_due
    end
    alias eql? ==

    def hash = [card.id, nominal_closing, nominal_due].hash
  end
end
