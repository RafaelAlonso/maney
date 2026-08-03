class AnalysesController < ApplicationController
  def show
    @years = selectable_years
    @year = resolve_year
    @cards = Card.order(:name)
    @card = resolve_card
    @analysis = Budgeting::YearAnalysis.new(year: @year, card: @card)
    # Independent of @year on purpose: the block looks forward from today, so the
    # picker does not govern it — and it is not card-scoped either.
    @solvency = Budgeting::Solvency.new
    @palette = Analysis::Palette.new
  end

  private

  # The picker stops at the current year on purpose. Months not yet reached are
  # drawn empty and excluded from every average (the story's rule), so a future
  # year would render entirely empty — offering it would be a dead end. Committed
  # future debt is the solvency story's subject, not this section's.
  def selectable_years
    first = Setting.instance.first_month.year
    (first..[ Date.current.year, first ].max).to_a.reverse
  end

  # A year that is unparseable, out of range or absent lands on something
  # sensible rather than raising: the picker is the supported path, and a
  # hand-edited or stale URL should still open a page.
  def resolve_year
    requested = params[:year].to_i
    return @years.first if requested.zero?
    requested.clamp(@years.last, @years.first)
  end

  # `find_by` rather than `find`: a blank, stale or hand-edited card_id lands on
  # "todos os cartões" instead of raising, the same forgiving policy resolve_year
  # documents above.
  #
  # Card.order(:name) and never Card.active — an archived card's history is real
  # spending and stays selectable (the sibling archiving story adds that scope;
  # it must not reach this screen).
  def resolve_card = Card.find_by(id: params[:card_id])
end
