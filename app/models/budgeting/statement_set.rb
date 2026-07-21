module Budgeting
  # Faturas derivadas dos gastos lançados — só existe fatura onde existe gasto.
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

    def due_in(month:)
      target = month.beginning_of_month
      Card.includes(:card_schedules).flat_map do |card|
        for_card(card:).select { |statement, _| statement.effective_due.beginning_of_month == target }.to_a
      end.to_h
    end
  end
end
