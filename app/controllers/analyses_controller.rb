class AnalysesController < ApplicationController
  def show
    @years = selectable_years
    @year = resolve_year
    @analysis = Budgeting::YearAnalysis.new(year: @year)
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
end
