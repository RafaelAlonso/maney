module Budgeting
  # The card bills Início shows under "saldo atual": every statement due in the
  # month (in StatementsDue order), then any past statement still unpaid, oldest
  # first — so an overdue bill can't silently drop off the screen. Statements
  # due before tracking started are never overdue: the old unlinked payments
  # can't be matched to them.
  class MonthBills
    Row = Data.define(:statement, :amount_cents, :remaining_cents, :status, :overdue)

    attr_reader :month

    def initialize(month:, today: Date.current, by_due_month: nil)
      @month = month.beginning_of_month
      @today = today
      @by_due_month = by_due_month
    end

    def rows
      @rows ||= due_rows + overdue_rows
    end

    def any? = rows.any?

    private

    def by_due_month
      @by_due_month ||= StatementSet.by_due_month
    end

    def payments
      @payments ||= StatementPayments.new(by_due_month:)
    end

    def due_rows
      StatementsDue.new(month:, by_due_month:).rows.map do |row|
        build(row.statement, row.amount_cents, overdue: false)
      end
    end

    def overdue_rows
      by_due_month.select { |due_month, _| due_month < month }
                  .flat_map { |_, statements| statements.map { |statement, expenses| build(statement, expenses.sum(&:amount_cents), overdue: true) } }
                  .select { |row| row.status != :untracked && row.remaining_cents.positive? && row.statement.effective_due < @today }
                  .sort_by { |row| [ row.statement.effective_due, row.statement.card.name, row.statement.card.id ] }
    end

    def build(statement, amount_cents, overdue:)
      Row.new(statement:, amount_cents:, remaining_cents: payments.remaining_cents(statement, amount_cents),
              status: payments.status(statement, amount_cents), overdue:)
    end
  end
end
