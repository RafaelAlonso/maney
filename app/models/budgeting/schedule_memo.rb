module Budgeting
  # Per-derivation memo of the cards' validity windows, created by whoever starts
  # a derivation (CardStatements, StatementSet) and passed down the attribution
  # chain. Attribution walks a statement window day by day, and every step needs
  # the window in effect — without a memo that is one query per day.
  #
  # Deliberately an ordinary object with no global reach: it lives only as long
  # as the derivation that built it, so a write that skips the model callbacks
  # (update_all, a data migration, a console fix) can never be served a stale
  # validity window on a later request. See the comment on Budgeting::Schedule.
  class ScheduleMemo
    def initialize
      @windows = {}
    end

    # The card's validity windows, oldest first — loaded once per card.
    def windows_for(card)
      return card.card_schedules.order(:valid_from).to_a if card.id.nil?

      @windows[card.id] ||= card.card_schedules.order(:valid_from).to_a
    end
  end
end
