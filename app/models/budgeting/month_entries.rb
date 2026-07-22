module Budgeting
  # Gastos exibíveis de um mês: os com data dentro do mês civil + as
  # parcelas cuja competência cai no mês. Só leitura, para as listas.
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
