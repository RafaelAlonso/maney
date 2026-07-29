module Budgeting
  # "Saldo estimado": the cash expected to remain at month end, assuming budgets
  # are spent in full and the statements due this month are paid. The counterpart
  # of BalanceChain, which owns "saldo atual".
  #
  # A credit purchase never reduces this at purchase time — it reduces it in the
  # month its statement comes due, through the reserved "cartão de crédito"
  # category. That is the whole point: subtracting it at purchase time AND again
  # at the due date was the double count this replaced.
  #
  # Takes the MonthSummary rather than a month, to reuse its memoization —
  # deriving the month's statements walks every card and every installment.
  module CashForecast
    module_function

    def estimated_balance_cents(summary)
      summary.incomes_total_cents - ordinary_committed(summary) - card_committed(summary)
    end

    # `role` is null on most categories — Category.where.not(role: "credit_card")
    # would exclude those rows via SQL three-valued logic, so we filter in Ruby.
    def ordinary_committed(summary)
      Category.all.reject(&:credit_card?).sum { |category| category_committed(summary, category) }
    end

    # Unspent budget is assumed to leave as cash: money not yet committed to a
    # card can still come out of the account this month. Credit purchases eat into
    # that budget without subtracting anything themselves.
    def category_committed(summary, category)
      cash   = summary.cash_spent_cents(category)
      credit = summary.spent_cents(category) - cash
      [[summary.budgeted_cents(category) - credit, 0].max, cash].max
    end

    def card_committed(summary)
      [summary.statements_due_cents, summary.statement_payments_cents].max
    end
  end
end
