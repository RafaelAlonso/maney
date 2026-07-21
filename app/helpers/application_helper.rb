module ApplicationHelper
  # O sinal vem antes do "R$", como em qualquer app bancário brasileiro:
  # saldo negativo é um número que se lê de relance, e um "-" escondido depois
  # do prefixo é fácil de não ver. Saldo carregado e saldo inicial podem ser
  # negativos, então esta é a forma que as telas mostram de verdade.
  def brl(cents)
    return "—" if cents.nil?
    return "-R$ #{BrlMoney.format(cents.abs)}" if cents.negative?
    "R$ #{BrlMoney.format(cents)}"
  end
end
