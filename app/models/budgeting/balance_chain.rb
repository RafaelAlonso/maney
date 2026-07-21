module Budgeting
  # Cadeia de saldos: o saldo inicial ancora o primeiro mês; cada mês
  # seguinte carrega o saldo atual do anterior. Sempre derivado, nunca
  # gravado — um lançamento retroativo muda a cadeia inteira à frente.
  module BalanceChain
    module_function

    def carried_into(month:)
      setting = Setting.instance
      target = month.beginning_of_month
      return 0 if setting.nil? || target < setting.first_month

      carried = setting.initial_balance_cents
      cursor = setting.first_month
      while cursor < target
        carried = current_balance(month: cursor, carried:)
        cursor = cursor >> 1
      end
      carried
    end

    # Saldo atual: ganhos (com o carregado) menos débito/dinheiro do mês.
    # Compras no crédito nunca entram; independe da data de hoje.
    def current_balance(month:, carried:)
      range = month.beginning_of_month.all_month
      incomes = Income.where(date: range).sum(:amount_cents)
      outflows = Expense.where(payment_method: %w[debit cash], date: range).sum(:amount_cents)
      carried + incomes - outflows
    end
  end
end
