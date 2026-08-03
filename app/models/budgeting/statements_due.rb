module Budgeting
  # The statements falling due in one month, across every card — the structure
  # StatementSet.due_in already returns, kept instead of flattened away. Nothing
  # here decides which statement a purchase lands on or when it falls due; that
  # stays in StatementAttribution and Statement.
  #
  # A row is one STATEMENT, not one card: a schedule change can leave two of one
  # card's statements due in the same calendar month, and the two have different
  # due dates and different URLs, so merging them would have nowhere unambiguous
  # to link.
  #
  # A card with nothing due cannot produce a row, and a quiet month produces
  # none — not by a guard, but because due_in is keyed by statements that exist,
  # and a statement exists only where an expense does.
  class StatementsDue
    Row = Data.define(:statement, :amount_cents)

    attr_reader :month

    def initialize(month:)
      @month = month.beginning_of_month
    end

    # Ordered by due date first — the order the statements are paid — then card
    # name to break a same-day tie, then card id so two cards sharing a name
    # still have a stable order.
    def rows
      @rows ||= StatementSet.due_in(month:)
                            .map { |statement, expenses| Row.new(statement:, amount_cents: expenses.sum(&:amount_cents)) }
                            .sort_by { |row| [ row.statement.effective_due, row.statement.card.name, row.statement.card.id ] }
    end

    def any? = rows.any?

    def total_cents = rows.sum(&:amount_cents)
  end
end
