# The color state and fill of a category's budget bar, derived only from figures
# that already exist (spent, budgeted) — no number is invented. `over` is
# strictly spent > budgeted (matching home/_category_row today); an unbudgeted
# category (budget 0) is neutral, not an overrun. `near` reuses the user's own
# alert threshold — the same "warn me when I'm close" knob from Configurações —
# so the amber band needs no new setting.
class BudgetBar
  def initialize(spent_cents:, budgeted_cents:, threshold_percent:)
    @spent = spent_cents
    @budgeted = budgeted_cents
    @threshold_percent = threshold_percent
  end

  def state
    return :neutral unless @budgeted.positive?
    return :over if @spent > @budgeted
    return :near if @spent >= @budgeted * @threshold_percent / 100.0
    :on_track
  end

  def fill_percent
    return 0 unless @budgeted.positive?
    [ (@spent * 100.0 / @budgeted).round, 100 ].min
  end
end
