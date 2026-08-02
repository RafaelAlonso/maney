module Budgeting
  # Which month each expense counts in, for any Expense scope. The caller
  # decides *which* expenses (the year screen excludes the reserved category;
  # the category drill-down scopes to one category); this module decides *when*.
  #
  # It exists so the competence read has exactly one implementation. Two screens
  # now ask this question, and the drill-down story treats a divergence between
  # them as a defect.
  module CompetenceSpending
    module_function

    def entries(scope:, year:)
      dated(scope, year) + undated(scope, year)
    end

    # The straightforward half: a dated expense counts in the month of its date.
    def dated(scope, year)
      range = Date.new(year, 1, 1)..Date.new(year, 12, 31)
      scope.where(date: range).map { |expense| [ expense, expense.date.beginning_of_month ] }
    end

    # Installments carry `date: nil` — their month comes from Competence, not
    # from a stored date, so they cannot be range-queried and are filtered in
    # Ruby (as MonthEntries.expenses already does). A date window on the
    # purchase is no substitute either: installments_count runs to 120, so a
    # purchase made ten years earlier can still land a parcel inside this year.
    def undated(scope, year)
      scope.where(date: nil).includes(:installment_purchase).filter_map do |expense|
        month = Competence.month_of(expense)
        [ expense, month ] if month.year == year
      end
    end
  end
end
