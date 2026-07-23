module Budgeting
  # Balance chain: the initial balance anchors the first month; each following
  # month carries the current balance from the previous one. Always derived,
  # never stored — a retroactive entry changes the whole chain ahead.
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

    # Current balance: incomes (plus the carried balance) minus the month's
    # debit/cash. Credit purchases never count; independent of today's date.
    def current_balance(month:, carried:)
      range = month.beginning_of_month.all_month
      incomes = Income.where(date: range).sum(:amount_cents)
      outflows = Expense.where(payment_method: %w[debit cash], date: range).sum(:amount_cents)
      carried + incomes - outflows
    end
  end
end
