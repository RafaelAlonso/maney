module Budgeting
  # Aggregate of a civil month: incomes, spent vs. budgeted per category and the
  # two balances. Everything derived on the fly; no value is stored.
  class MonthSummary
    attr_reader :month

    def initialize(month:, today: Date.current)
      @month = month.beginning_of_month
      @today = today
    end

    def carried_balance_cents
      @carried_balance_cents ||= BalanceChain.carried_into(month:)
    end

    # The month's own incomes, in the order the screens list them. The carried
    # balance is NOT one of them — it's derived, has no row, and is presented
    # separately (see `carried_balance_cents`) — but it does count towards the
    # total, which is what the estimate spends against.
    def incomes
      @incomes ||= Income.where(date: month.all_month).order(:date, :name).to_a
    end

    def incomes_total_cents
      carried_balance_cents + incomes.sum(&:amount_cents)
    end

    def spent_cents(category)
      if category.credit_card?
        statement_payments_cents
      else
        dated = Expense.where(category:, date: month.all_month).sum(:amount_cents)
        dated + installment_spent_cents(category)
      end
    end

    # The cash half of a category's month: what actually left the account. The
    # credit half is `spent_cents - cash_spent_cents` — installments carry
    # `date: nil` and are always `payment_method: "credit"`, so they are excluded
    # here by construction, and the two halves always reconcile to the total the
    # budgeted-vs-spent rows show.
    def cash_spent_cents(category)
      Expense.where(category:, payment_method: %w[debit cash], date: month.all_month)
             .sum(:amount_cents)
    end

    # Public because Budgeting::CashForecast must reach these without going
    # through the reserved category — that row is deletable, and reaching them via
    # `budgeted_cents(credit_card_category)` made the estimate discard a whole
    # statement when it was missing.
    #
    # Memoized because deriving the month's statements walks every card and every
    # installment — expensive, and asked for more than once per summary (the
    # reserved category's budgeted amount and the forecast use the same number).
    # Safe for the same reason as carried_balance_cents: the instance is
    # disposable, for a single month. Nothing here may become process state (see
    # Budgeting::Schedule).
    def statements_due_cents
      @statements_due_cents ||= StatementSet.due_in(month:).values.flatten.sum(&:amount_cents)
    end

    # Payments entered against statements: filtered by role, not by a reference to
    # the reserved category record, for the same reason.
    def statement_payments_cents
      @statement_payments_cents ||=
        Expense.joins(:category)
               .where(categories: { role: "credit_card" }, payment_method: %w[debit cash], date: month.all_month)
               .sum(:amount_cents)
    end

    def budgeted_cents(category)
      return statements_due_cents if category.credit_card?

      budget = Budget.find_by(category:, month:)
      return budget.amount_cents if budget

      inherited_budget_cents(category)
    end

    # The definition lives in Budgeting::CashForecast — see it for what this
    # number means and what it deliberately does not count.
    def estimated_balance_cents = CashForecast.estimated_balance_cents(self)

    def current_balance_cents
      BalanceChain.current_balance(month:, carried: carried_balance_cents)
    end

    private

    def installment_spent_cents(category)
      Expense.where(category:, date: nil).includes(:installment_purchase).sum do |expense|
        Competence.month_of(expense) == month ? expense.amount_cents : 0
      end
    end

    # Inherited budget: with no explicit Budget for the month, a category's
    # budget is what it spent the previous month (including zero), held until the
    # user sets one. The first month has nothing before it, so it inherits zero.
    # `spent_cents` already counts projected installments, so future months chain
    # naturally (June inherits May's projected spending) with no recursion —
    # inheritance reads spending, never another month's budget.
    def inherited_budget_cents(category)
      previous = month << 1
      first = Setting.instance&.first_month
      return 0 if first.nil? || previous < first

      MonthSummary.new(month: previous, today: @today).spent_cents(category)
    end
  end
end
