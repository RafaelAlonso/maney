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
      # One memo for this whole derivation: the card's validity windows are read
      # once instead of once per day walked back from each statement's closing.
      # It dies with this object, so nothing can be served a stale window later.
      @memo = ScheduleMemo.new
    end

    def rows
      @rows ||= StatementSet.for_card(card: @card, memo: @memo)
                            .map { |statement, expenses| build_row(statement, expenses) }
    end

    def empty? = rows.empty?

    # The open statement and every one after it, in chronological order — the
    # ones the user still acts on. `Statement#open?` is true for both, so a
    # single partition gives the block.
    def open = partition.first

    # History, newest first.
    def closed = partition.last

    # The URL id is a nominal closing date. Two statements can share one when a
    # schedule change lands on the same closing day with a different due day
    # (the due date is part of the natural identity); the earlier due date wins,
    # which is the older of the two.
    def find(nominal_closing)
      rows.select { |row| row.statement.nominal_closing == nominal_closing }
          .min_by { |row| row.statement.nominal_due }
    end

    private

    def partition
      @partition ||= begin
        open_rows, closed_rows = rows.partition { |row| row.statement.open?(today: @today) }
        [ open_rows.sort_by { |row| row.statement.effective_due },
         closed_rows.sort_by { |row| row.statement.effective_due }.reverse ]
      end
    end

    def build_row(statement, expenses)
      period_end = statement.effective_closing - 1
      Row.new(
        statement:,
        expenses: expenses.sort_by { |expense| [ expense.date || period_end, expense.name ] },
        total_cents: expenses.sum(&:amount_cents),
        # NOT obtained by walking the chain backward with `succ`: `succ`
        # re-resolves the validity window at each closing, so the chain can move
        # backward and a traversal based on it misses the boundary. See the
        # comment on StatementAttribution.window_start.
        period_start: StatementAttribution.window_start(card: @card, date: period_end, memo: @memo),
        period_end:
      )
    end
  end
end
