module Budgeting
  # "Saldo estimado": the cash expected to remain at month end, assuming budgets
  # are spent in full and the statements due this month are paid. The counterpart
  # of BalanceChain, which owns "saldo atual".
  #
  # A credit purchase never reduces this at purchase time — it reduces it in the
  # month its statement comes due, as the card term — the same total the
  # reserved "cartão de crédito" row displays, but read from the statements
  # themselves, never from that (deletable) category row. That is the whole
  # point: subtracting it at purchase time AND again at the due date was the
  # double count this replaced.
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
      [ [ summary.budgeted_cents(category) - credit, 0 ].max, cash ].max
    end

    # Cash the cards take out this month. A linked payment is cash out in the
    # month it is made; a statement due this month still needs cash only for
    # what hasn't been paid yet. Unlinked payments keep the old max(due, paid).
    # With nothing linked this is exactly max(statements due, payments) — and
    # reading linked payments by due month alone would double-count an early
    # one: it is already out of the carried balance.
    #
    # A statement due in a PAST month that was never paid contributes nothing
    # here — the solvency block owns arrears.
    def card_committed(summary)
      payments = summary.statement_payments
      remaining_due = summary.statements_due.rows.sum do |row|
        payments.remaining_cents(row.statement, row.amount_cents)
      end
      payments.linked_paid_in(summary.month) + [ remaining_due, payments.unlinked_paid_in(summary.month) ].max
    end
  end
end
