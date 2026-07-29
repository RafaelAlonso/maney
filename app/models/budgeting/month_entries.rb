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
      (dated.to_a + undated).sort_by { |expense| [listing_date(expense, target), expense.name] }
    end

    # The date a row is listed under. An installment carries `date: nil` (its
    # month comes from the schedule, not from a stored date), and falling back to
    # the 1st collapsed every installment onto the top of the list, above
    # expenses actually made earlier in the month. The purchase's day-of-month is
    # what the user recognises as "when this was bought", so it stands in —
    # clamped, because a purchase on the 31st has no counterpart in a 30-day
    # month. Sorting only; nothing here is stored or shown as the row's date.
    def listing_date(expense, month)
      return expense.date if expense.date

      purchase_day = expense.installment_purchase.date.day
      month.change(day: [purchase_day, month.end_of_month.day].min)
    end
  end
end
