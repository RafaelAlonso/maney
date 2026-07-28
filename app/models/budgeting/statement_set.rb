module Budgeting
  # Statements derived from the entered expenses — a statement exists only where an expense does.
  module StatementSet
    module_function

    def statement_of(expense)
      if expense.installment?
        StatementAttribution.statement_for_installment(
          purchase: expense.installment_purchase, number: expense.installment_number
        )
      else
        StatementAttribution.statement_for(card: expense.card, date: expense.date)
      end
    end

    def for_card(card:)
      card.expenses.where(payment_method: "credit").includes(:installment_purchase)
          .group_by { |expense| statement_of(expense) }
    end

    # Statement labels for a list of expenses: {expense_id => Statement}, credit
    # ones only. Derives each card's set once instead of calling `statement_of`
    # per row — which issues a Schedule query per expense, plus one per link of
    # every installment's `succ` chain.
    #
    # It does derive a card's whole history to label one month's rows. At this
    # scale that is cheap and it keeps attribution on a single code path; if it
    # ever stops being cheap, the fix is the memo passed along by derivation that
    # Budgeting::Schedule's comment describes — never a second attribution
    # implementation, and never process-global state.
    def labels_for(expenses)
      credit = expenses.select { |expense| expense.payment_method == "credit" }
      wanted = credit.map(&:id)
      credit.filter_map(&:card).uniq.each_with_object({}) do |card, labels|
        for_card(card:).each do |statement, card_expenses|
          card_expenses.each { |expense| labels[expense.id] = statement if wanted.include?(expense.id) }
        end
      end
    end

    def due_in(month:)
      target = month.beginning_of_month
      Card.includes(:card_schedules).flat_map do |card|
        for_card(card:).select { |statement, _| statement.effective_due.beginning_of_month == target }.to_a
      end.to_h
    end
  end
end
