module Budgeting
  # Competence month of an expense: the purchase month; installment k consumes
  # the k-th month from the purchase month (anchor = first installment created).
  module Competence
    module_function

    def month_of(expense)
      if expense.installment?
        purchase = expense.installment_purchase
        purchase.date.beginning_of_month >> (expense.installment_number - purchase.first_installment)
      else
        expense.date.beginning_of_month
      end
    end
  end
end
