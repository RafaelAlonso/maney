module Budgeting
  # Visual alert: do next month's statements threaten this month's current
  # balance? Red when they exceed it; yellow when they reach a configurable share
  # of it (default 80%); none otherwise. Purely derived, like everything here.
  # A zero next-month total is never an alert; a non-positive balance with any
  # statement is red (any positive total exceeds a non-positive balance).
  class StatementAlert
    def initialize(month:, today: Date.current)
      @month = month.beginning_of_month
      @today = today
    end

    # :red | :yellow | :none
    def level
      return :none if next_statements_cents.zero?
      return :red if next_statements_cents > current_balance_cents
      return :yellow if next_statements_cents >= threshold_cents

      :none
    end

    private

    # What is still owed on them: a statement already paid (through pagar)
    # threatens nothing.
    def next_statements_cents
      @next_statements_cents ||= begin
        by_due_month = StatementSet.by_due_month
        payments = StatementPayments.new(by_due_month:)
        by_due_month.fetch(@month >> 1, {}).sum do |statement, expenses|
          payments.remaining_cents(statement, expenses.sum(&:amount_cents))
        end
      end
    end

    def current_balance_cents
      @current_balance_cents ||= MonthSummary.new(month: @month, today: @today).current_balance_cents
    end

    def threshold_cents
      (current_balance_cents * threshold_percent) / 100
    end

    def threshold_percent
      Setting.instance&.alert_threshold_percent || 80
    end
  end
end
