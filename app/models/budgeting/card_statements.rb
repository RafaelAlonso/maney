module Budgeting
  # The card's statements ready for a screen: totalled, with the purchase period
  # of each. Derived on read like everything else here — nothing is stored, so an
  # entry, edit or deletion of an expense shows up on the next request with no
  # cache to invalidate.
  class CardStatements
    # period_end is the last day that still belongs to the statement: the window
    # is [previous effective closing, this effective closing), because a purchase
    # made on the effective closing date already belongs to the next statement.
    Row = Data.define(:statement, :expenses, :total_cents, :period_start, :period_end)

    def initialize(card:, today: Date.current)
      @card = card
      @today = today
    end

    def rows
      @rows ||= StatementSet.for_card(card: @card).map { |statement, expenses| build_row(statement, expenses) }
    end

    def empty? = rows.empty?

    private

    def build_row(statement, expenses)
      period_end = statement.effective_closing - 1
      Row.new(
        statement:,
        expenses: expenses.sort_by { |expense| [expense.date || period_end, expense.name] },
        total_cents: expenses.sum(&:amount_cents),
        # NOT obtained by walking the chain backward with `succ`: `succ`
        # re-resolves the validity window at each closing, so the chain can move
        # backward and a traversal based on it misses the boundary. See the
        # comment on StatementAttribution.window_start.
        period_start: StatementAttribution.window_start(card: @card, date: period_end),
        period_end:
      )
    end
  end
end
