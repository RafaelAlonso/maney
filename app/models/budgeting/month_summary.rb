module Budgeting
  # Agregado de um mês civil: ganhos, consumo vs. orçado por categoria e os
  # dois saldos. Tudo derivado na hora; nenhum valor é gravado.
  class MonthSummary
    attr_reader :month

    def initialize(month:, today: Date.current)
      @month = month.beginning_of_month
      @today = today
    end

    def carried_balance_cents
      @carried_balance_cents ||= BalanceChain.carried_into(month:)
    end

    def incomes_total_cents
      carried_balance_cents + Income.where(date: month.all_month).sum(:amount_cents)
    end

    def spent_cents(category)
      if category.credit_card?
        credit_card_spent_cents
      else
        dated = Expense.where(category:, date: month.all_month).sum(:amount_cents)
        dated + installment_spent_cents(category)
      end
    end

    def budgeted_cents(category)
      if category.credit_card?
        credit_card_budgeted_cents
      else
        Budget.find_by(category:, month:)&.amount_cents || 0
      end
    end

    def estimated_balance_cents
      # `role` é nulo na maioria das categorias — Category.where.not(role: "credit_card")
      # excluiria essas linhas por três-valores em SQL, então filtramos em Ruby.
      other_committed = Category.all.reject(&:credit_card?).sum { |c| [budgeted_cents(c), spent_cents(c)].max }
      incomes_total_cents - other_committed - credit_card_committed_cents
    end

    def current_balance_cents
      BalanceChain.current_balance(month:, carried: carried_balance_cents)
    end

    private

    # Termo do cartão de crédito calculado sem depender da linha reservada
    # existir em Category — o orçado vem inteiramente das faturas derivadas
    # e o consumido é filtrado pelo papel, não por uma referência à categoria.
    def credit_card_committed_cents
      [credit_card_budgeted_cents, credit_card_spent_cents].max
    end

    # Memoizados porque derivar as faturas do mês percorre todos os cartões e
    # todas as parcelas — caro, e pedido mais de uma vez por resumo (o orçado
    # da categoria reservada e o estimado usam o mesmo número). Seguro pelo
    # mesmo motivo que carried_balance_cents: a instância é descartável, de um
    # mês só. Nada aqui pode virar estado de processo (ver Budgeting::Schedule).
    def credit_card_budgeted_cents
      @credit_card_budgeted_cents ||= StatementSet.due_in(month:).values.flatten.sum(&:amount_cents)
    end

    def credit_card_spent_cents
      @credit_card_spent_cents ||=
        Expense.joins(:category)
               .where(categories: { role: "credit_card" }, payment_method: %w[debit cash], date: month.all_month)
               .sum(:amount_cents)
    end

    def installment_spent_cents(category)
      Expense.where(category:, date: nil).includes(:installment_purchase).sum do |expense|
        Competence.month_of(expense) == month ? expense.amount_cents : 0
      end
    end
  end
end
