module Budgeting
  # An expense's displayable entries for a month: those dated within the civil
  # month + the installments whose competence falls in the month. Read-only,
  # for the lists.
  module MonthEntries
    module_function

    def expenses(month:, category: nil)
      target = month.beginning_of_month
      dated = Expense.where(date: target.all_month).includes(:category, :card)
      dated = dated.where(category:) if category
      undated = Expense.where(date: nil).includes(:installment_purchase, :category, :card)
      undated = undated.where(category:) if category
      undated = undated.select { |expense| Competence.month_of(expense) == target }
      (dated.to_a + undated).sort_by { |expense| [expense.date || target, expense.name] }
    end
  end
end
