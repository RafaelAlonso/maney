class HomeController < ApplicationController
  # The Início list can be ordered by name, by budget or by spending, in either
  # direction; the percentage each card shows can read against income or against
  # the month's total spending. All three are per-user preferences: a value
  # arriving as a query param is remembered in a cookie and used on later plain
  # visits, so the screen keeps the shape the user last chose.
  SORTS = %w[name budget expenses].freeze
  DIRECTIONS = %w[asc desc].freeze
  PERCENT_MODES = %w[earnings expenses].freeze

  def show
    @summary = Budgeting::MonthSummary.new(month: current_month)
    @alert = Budgeting::StatementAlert.new(month: current_month)

    @sort = preference(:home_sort, params[:sort], SORTS, "name")
    @direction = preference(:home_dir, params[:dir], DIRECTIONS, "asc")
    @percent_mode = preference(:home_percent, params[:percent], PERCENT_MODES, "expenses")

    @categories = sorted_categories
    # The denominator for the "% of the month's spending" reading: the sum of what
    # every ordinary category consumed, credit-card statement payments excluded for
    # the same double-count reason the chart excludes them.
    @expenses_total_cents = @categories.reject(&:credit_card?).sum { |category| @summary.spent_cents(category) }
    @category_chart = Analysis::CategoryMonthChart.new(summary: @summary, categories: @categories)
  end

  private

  # A sort key over the derived (never stored) budget/spending figures, so the
  # ordering is done in Ruby — there is no column to ORDER BY. Name is the
  # stable tie-breaker, and the whole comparison reverses for a descending sort.
  def sorted_categories
    key =
      case @sort
      when "budget"   then ->(category) { [ @summary.budgeted_cents(category), category.name.downcase ] }
      when "expenses" then ->(category) { [ @summary.spent_cents(category), category.name.downcase ] }
      else                 ->(category) { [ category.name.downcase ] }
      end
    ordered = Category.all.to_a.sort_by(&key)
    @direction == "desc" ? ordered.reverse : ordered
  end

  # Resolve a preference: a valid query param wins and is remembered; otherwise a
  # previously remembered value is used; otherwise the default. `cookies.permanent`
  # gives it a far-future expiry so the choice survives the session.
  def preference(cookie, param, allowed, default)
    if allowed.include?(param)
      cookies.permanent[cookie] = param
      param
    elsif allowed.include?(cookies[cookie])
      cookies[cookie]
    else
      default
    end
  end
end
