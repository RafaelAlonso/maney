module Budgeting
  # (data da compra, vigência do cartão) -> fatura. Determinístico: a fatura
  # é a primeira cujo fechamento efetivo é posterior à data da compra —
  # compra na data efetiva de fechamento vai para a seguinte.
  module StatementAttribution
    module_function

    def statement_for(card:, date:)
      schedule = Schedule.for(card:, date:)
      cycle = (date << 1).beginning_of_month
      loop do
        statement = Statement.new(card:, cycle:, schedule:)
        return statement if statement.effective_closing > date
        cycle = cycle >> 1
      end
    end

    # Parcela k: fatura da compra avançada (k - primeira parcela criada)
    # faturas — sequência por fatura, sem data própria.
    def statement_for_installment(purchase:, number:)
      statement = statement_for(card: purchase.card, date: purchase.date)
      (number - purchase.first_installment).times { statement = statement.succ }
      statement
    end
  end
end
