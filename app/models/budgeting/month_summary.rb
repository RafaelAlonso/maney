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
      # `role` is null on most categories — Category.where.not(role: "credit_card")
      # would exclude those rows via SQL three-valued logic, so we filter in Ruby.
      other_committed = Category.all.reject(&:credit_card?).sum { |c| [budgeted_cents(c), spent_cents(c)].max }
      incomes_total_cents - other_committed - credit_card_committed_cents
    end

    def current_balance_cents
      BalanceChain.current_balance(month:, carried: carried_balance_cents)
    end

    private

    # Credit-card term computed without relying on the reserved row existing in
    # Category — the budgeted amount comes entirely from the derived statements
    # and the spent amount is filtered by role, not by a reference to the category.
    def credit_card_committed_cents
      [credit_card_budgeted_cents, credit_card_spent_cents].max
    end

    # Memoized because deriving the month's statements walks every card and every
    # installment — expensive, and asked for more than once per summary (the
    # reserved category's budgeted amount and the estimate use the same number).
    # Safe for the same reason as carried_balance_cents: the instance is
    # disposable, for a single month. Nothing here may become process state (see
    # Budgeting::Schedule).
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
