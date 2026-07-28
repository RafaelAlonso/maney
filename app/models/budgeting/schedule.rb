module Budgeting
  # The card's day settings in effect on a date. Editing the card's days = a new
  # row in card_schedules effective from the open window onward; closed
  # statements stay derived from the old validity window.
  #
  # The query is always redone: nothing here is memoized. A process cache was
  # once written and reverted — it served a stale validity window after any write
  # that skipped the model callbacks (update_all, a data migration, a console
  # fix), i.e. wrong money out of correct-looking code. If the per-query cost
  # becomes a problem once there's a screen, memoize by derivation (a memo passed
  # along by StatementSet/MonthSummary), never in global state. That memo is
  # Budgeting::ScheduleMemo: pass one in `memo:` and the windows are read from it
  # instead of from the database; leave it out and the query is redone, as here.
  Schedule = Data.define(:closing_day, :due_day, :valid_from) do
    def self.for(card:, date:, memo: nil)
      # The window in effect on `date` is the latest one starting no later than
      # it; before the card's timeline starts, the oldest one stands in.
      rows = windows(card:, memo:)
      row = rows.reverse_each.find { |window| window.valid_from <= date } || rows.first
      raise ArgumentError, "card #{card.id} has no schedule" if row.nil?
      new(closing_day: row.closing_day, due_day: row.due_day, valid_from: row.valid_from)
    end

    # The card's validity windows, oldest first.
    def self.windows(card:, memo: nil)
      memo ? memo.windows_for(card) : card.card_schedules.order(:valid_from).to_a
    end
  end
end
