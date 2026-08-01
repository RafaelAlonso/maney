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
      @calendar = YearCalendar.new(year:, today:)
    end

    def months = @calendar.months

    # The months that actually happened. Delegated to YearCalendar, which the
    # category drill-down shares — this predicate is still the whole of AC 9,
    # AC 10 and the average rule, and no chart re-derives it.
    def active_months = @calendar.active_months

    def active?(month) = @calendar.active?(month)

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

    # Income rows only. The carried balance is deliberately NOT included: it is
    # last month's leftover, not income earned this month, and adding it would
    # compound across the year — every month after a good one would read as
    # profitable. MonthSummary#incomes_total_cents does include it because the
    # month screen spends against it; the two answer different questions and are
    # allowed to disagree.
    def income
      @income ||= series(by_month(Income.where(date: year_range).group(:date).sum(:amount_cents)))
    end

    # What actually left the account. Statement payments live in the reserved
    # category with a debit/cash method, so they are counted here by
    # construction — and never filtered by category, unlike spending.
    def cash_outflow
      @cash_outflow ||= series(by_month(
        Expense.where(payment_method: %w[debit cash], date: year_range).group(:date).sum(:amount_cents)
      ))
    end

    def profit_vs_spending = @profit_vs_spending ||= income - spending

    def profit_vs_outflow = @profit_vs_outflow ||= income - cash_outflow

    def any_data? = spending.any? || income.any? || cash_outflow.any?

    private

    def year_range = Date.new(@year, 1, 1)..Date.new(@year, 12, 31)

    def series(amounts) = MonthlySeries.new(months:, active_months:, amounts:)

    # Rolls a `{Date => cents}` result up to `{month => cents}`. Grouping by the
    # raw date and folding in Ruby keeps the query portable and the volume is
    # trivially small at this scale.
    def by_month(sums_by_date)
      sums_by_date.each_with_object(Hash.new(0)) do |(date, cents), totals|
        totals[date.beginning_of_month] += cents
      end
    end

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
