module Budgeting
  # One category's year: its spending by competence, month by month, as a
  # MonthlySeries. Everything derived on the fly; no value is stored.
  #
  # It deliberately restates nothing. YearCalendar owns which months happened,
  # CompetenceSpending owns which month an expense counts in, and MonthlySeries
  # owns the average-over-active-months rule and the gaps. That is why the
  # drill-down's numbers cannot drift from the year screen's.
  #
  # No reserved-category branch: the year screen excludes "cartão de crédito"
  # because counting it there would double-count consumption, but on its own
  # screen its content *is* its statement payments — which this same rule
  # returns, since a statement payment is debit or cash with a real date.
  class CategoryYear
    attr_reader :year

    def initialize(category:, year:, today: Date.current)
      @category = category
      @year = year
      @calendar = YearCalendar.new(year:, today:)
    end

    def spending
      @spending ||= MonthlySeries.new(months: @calendar.months,
                                      active_months: @calendar.active_months,
                                      amounts: totals_by_month)
    end

    def any_data? = spending.any?

    private

    def totals_by_month
      CompetenceSpending.entries(scope: @category.expenses, year: @year)
                        .each_with_object(Hash.new(0)) do |(expense, month), totals|
        totals[month] += expense.amount_cents
      end
    end
  end
end
