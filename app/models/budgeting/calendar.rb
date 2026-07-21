module Budgeting
  # Regras de data do cartão: transbordo de dia inexistente e ajuste a dia
  # útil (fechamento recua, vencimento avança). Feriados fora de escopo.
  module Calendar
    module_function

    def nominal_date(year, month, day)
      Date.new(year, month, 1) + (day - 1)
    end

    def effective_closing(nominal)
      date = nominal
      date -= 1 while date.saturday? || date.sunday?
      date
    end

    def effective_due(nominal)
      date = nominal
      date += 1 while date.saturday? || date.sunday?
      date
    end
  end
end
