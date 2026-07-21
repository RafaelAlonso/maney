module Budgeting
  # Fatura derivada — nunca persistida. Identidade natural:
  # (cartão, data nominal de fechamento).
  class Statement
    attr_reader :card, :cycle, :schedule

    def initialize(card:, cycle:, schedule:)
      @card = card
      @cycle = cycle.beginning_of_month
      @schedule = schedule
    end

    def nominal_closing = Calendar.nominal_date(cycle.year, cycle.month, schedule.closing_day)
    def effective_closing = Calendar.effective_closing(nominal_closing)

    # Vencimento menor que o fechamento => vence no mês seguinte ao do ciclo.
    def nominal_due
      base = schedule.due_day < schedule.closing_day ? cycle >> 1 : cycle
      Calendar.nominal_date(base.year, base.month, schedule.due_day)
    end

    def effective_due = Calendar.effective_due(nominal_due)

    def closed?(today:) = effective_closing <= today
    def open?(today:) = !closed?(today:)

    def succ
      next_cycle = cycle >> 1
      Statement.new(card:, cycle: next_cycle, schedule: Schedule.for(card:, date: next_cycle))
    end

    def ==(other)
      other.is_a?(Statement) && other.card.id == card.id && other.nominal_closing == nominal_closing
    end
    alias eql? ==

    def hash = [card.id, nominal_closing].hash
  end
end
