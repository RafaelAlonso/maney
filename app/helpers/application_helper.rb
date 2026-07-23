module ApplicationHelper
  # The sign comes before the "R$", as in any Brazilian banking app: a negative
  # balance is a number read at a glance, and a "-" hidden after the prefix is
  # easy to miss. The carried balance and the initial balance can be negative, so
  # this is how the screens actually show it.
  def brl(cents)
    return "—" if cents.nil?
    return "-R$ #{BrlMoney.format(cents.abs)}" if cents.negative?
    "R$ #{BrlMoney.format(cents)}"
  end

  # Single source for the payment-method labels — used by the expense form
  # (radios) and the expense row (`expenses/_row`, reused by categories#show).
  # Repeating this hash in every view is how Task 6 found the original form: the
  # same translation transcribed three times.
  PAYMENT_METHOD_LABELS = { "credit" => "crédito", "debit" => "débito", "cash" => "dinheiro" }.freeze

  def payment_method_labels = PAYMENT_METHOD_LABELS

  def payment_method_label(method) = PAYMENT_METHOD_LABELS[method]
end
