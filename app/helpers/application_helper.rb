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

  # Única fonte para os rótulos de método de pagamento — usada pelo form de
  # gasto (radios) e pela linha de gasto (`expenses/_row`, reaproveitada por
  # categories#show). Repetir este hash em cada view é como o Task 6 achou o
  # form original: a mesma tradução transcrita três vezes.
  PAYMENT_METHOD_LABELS = { "credit" => "crédito", "debit" => "débito", "cash" => "dinheiro" }.freeze

  def payment_method_labels = PAYMENT_METHOD_LABELS

  def payment_method_label(method) = PAYMENT_METHOD_LABELS[method]
end
