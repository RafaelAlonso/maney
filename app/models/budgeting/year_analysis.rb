module Budgeting
  # One calendar year, read four ways: spending by competence, spending split by
  # category, income, and cash outflow. Everything derived on the fly; no value
  # is stored.
  #
  # Deliberately does NOT go through MonthSummary, BalanceChain or StatementSet.
  # Those are per-month and recursive — calling them twelve times would be slow,
  # and wrong for this story's definitions: profit here excludes the carried
  # balance (see #income), and statement attribution is irrelevant to a
  # competence-based chart.
  class YearAnalysis
    def initialize(year:, today: Date.current)
      @year = year
      @today = today
    end

    def months
      @months ||= (1..12).map { |month| Date.new(@year, month, 1) }
    end

    # The months that actually happened: on or after the first month, and not in
    # the future. This single predicate is the whole of AC 9, AC 10 and the
    # average rule — no chart re-derives it.
    def active_months
      @active_months ||= begin
        first = Setting.instance&.first_month
        last = @today.beginning_of_month
        first.nil? ? [] : months.select { |month| month >= first && month <= last }
      end
    end

    def active?(month) = active_months.include?(month)

    def spending
      @spending ||= series(spending_by_category.values.each_with_object(Hash.new(0)) do |category_series, totals|
        months.each { |month| totals[month] += category_series.cents(month) }
      end)
    end

    def spending_by_category
      @spending_by_category ||= build_spending
    end

    def categories
      @categories ||= spending_by_category.keys.sort_by { |category| -spending_by_category[category].total_cents }
    end

    private

    def year_range = Date.new(@year, 1, 1)..Date.new(@year, 12, 31)

    def series(amounts) = MonthlySeries.new(months:, active_months:, amounts:)

    def build_spending
      totals = Hash.new { |hash, key| hash[key] = Hash.new(0) }
      dated_spending.each do |expense|
        totals[expense.category][expense.date.beginning_of_month] += expense.amount_cents
      end
      installment_spending.each do |expense, month|
        totals[expense.category][month] += expense.amount_cents
      end
      totals.transform_values { |by_month| series(by_month) }
    end

    # The reserved category is excluded with a NOT IN subquery rather than
    # `where.not(categories: { role: "credit_card" })`: under SQL three-valued
    # logic the latter also drops every NULL-role category — which is nearly all
    # of them — and would silently empty the chart. Same trap
    # MonthSummary#estimated_balance_cents documents.
    def dated_spending
      Expense.includes(:category)
             .where(date: year_range)
             .where.not(category: Category.where(role: "credit_card"))
    end

    # Installments carry `date: nil` — their month comes from Competence, not
    # from a stored date, so they cannot be range-queried and are filtered in
    # Ruby (as MonthEntries.expenses already does). A date window on the
    # purchase buys little either: installments_count runs to 120, so the window
    # would have to reach ten years back to stay correct.
    def installment_spending
      Expense.where(date: nil)
             .includes(:installment_purchase, :category)
             .filter_map do |expense|
               next if expense.category.credit_card?
               month = Competence.month_of(expense)
               [ expense, month ] if month.year == @year
             end
    end
  end
end
