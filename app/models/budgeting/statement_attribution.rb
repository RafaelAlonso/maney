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

    # A data em que a janela que contém `date` abriu — o fechamento efetivo da
    # fatura anterior. Percorre a cadeia com succ de propósito: as fronteiras
    # relatadas aqui são, por construção, as mesmas que succ enxerga.
    def window_start(card:, date:)
      earliest = card.card_schedules.minimum(:valid_from)
      raise ArgumentError, "card #{card.id} has no schedule" if earliest.nil?
      return earliest if date <= earliest

      statement = statement_for(card:, date: earliest)
      start = earliest
      while statement.effective_closing <= date
        # Uma troca de vigência pode fazer succ recuar (fechar dia 31 -> dia 1
        # atravessa a virada do mês). Fronteira de janela não anda para trás:
        # se a cadeia deixou de avançar, a última fronteira real é a que vale.
        break if statement.effective_closing <= start

        start = statement.effective_closing
        statement = statement.succ
      end
      start
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
