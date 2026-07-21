module Budgeting
  # Mês de competência de um gasto: o mês da compra; parcela k consome o
  # k-ésimo mês a partir do mês da compra (âncora = primeira parcela criada).
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
