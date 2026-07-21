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

    # Início da janela de fatura que contém `date`: o menor dia que ainda cai
    # na mesma fatura que `date`. Definido pela própria função de atribuição,
    # e não caminhando a cadeia com succ: succ reresolve a vigência a cada
    # fechamento, então a cadeia pode recuar (fechar dia 31 -> dia 1 atravessa
    # a virada do mês) e qualquer travessia baseada nela erra a fronteira.
    # Assim a fronteira é, por construção, a mesma que statement_for enxerga.
    def window_start(card:, date:)
      earliest = card.card_schedules.minimum(:valid_from)
      raise ArgumentError, "card #{card.id} has no schedule" if earliest.nil?
      return earliest if date <= earliest

      target = statement_for(card:, date:)
      day = date
      day -= 1 while day > earliest && statement_for(card:, date: day - 1) == target
      day
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
