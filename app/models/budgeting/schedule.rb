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
  # along by StatementSet/MonthSummary), never in global state.
  Schedule = Data.define(:closing_day, :due_day, :valid_from) do
    def self.for(card:, date:)
      row = card.card_schedules.where(valid_from: ..date).order(valid_from: :desc).first ||
            card.card_schedules.order(:valid_from).first
      raise ArgumentError, "card #{card.id} has no schedule" if row.nil?
      new(closing_day: row.closing_day, due_day: row.due_day, valid_from: row.valid_from)
    end
  end
end
