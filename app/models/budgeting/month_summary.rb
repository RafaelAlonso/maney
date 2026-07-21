module Budgeting
  # Agregado de um mês civil: ganhos, consumo vs. orçado por categoria e os
  # dois saldos. Tudo derivado na hora; nenhum valor é gravado.
  class MonthSummary
    attr_reader :month

    def initialize(month:, today: Date.current)
      @month = month.beginning_of_month
      @today = today
    end

    def carried_balance_cents = BalanceChain.carried_into(month:)

    def incomes_total_cents
      carried_balance_cents + Income.where(date: month.all_month).sum(:amount_cents)
    end

    def spent_cents(category)
      if category.credit_card?
        Expense.where(category:, payment_method: %w[debit cash], date: month.all_month)
               .sum(:amount_cents)
      else
        dated = Expense.where(category:, date: month.all_month).sum(:amount_cents)
        dated + installment_spent_cents(category)
      end
    end

    def budgeted_cents(category)
      if category.credit_card?
        StatementSet.due_in(month:).values.flatten.sum(&:amount_cents)
      else
        Budget.find_by(category:, month:)&.amount_cents || 0
      end
    end

    def estimated_balance_cents
      committed = Category.find_each.sum { |c| [budgeted_cents(c), spent_cents(c)].max }
      incomes_total_cents - committed
    end

    def current_balance_cents
      BalanceChain.current_balance(month:, carried: carried_balance_cents)
    end

    private

    def installment_spent_cents(category)
      Expense.where(category:, date: nil).includes(:installment_purchase).sum do |expense|
        Competence.month_of(expense) == month ? expense.amount_cents : 0
      end
    end
  end
end
