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

  # The statement's EFFECTIVE due date — never the nominal one. The year appears
  # only when it differs from the current one, so a statement across the rollover
  # (a 12x bought in December) can't be read as this year's, while the everyday
  # label stays short.
  def statement_due_label(statement, today: Date.current)
    "vence #{statement_date(statement.effective_due, [statement.effective_due], today)}"
  end

  # The statement's purchase period: from the previous effective closing to the
  # day before this one. Same year rule as the due label, applied to both ends
  # together so the two dates always read in the same format.
  def statement_period_label(row, today: Date.current)
    dates = [row.period_start, row.period_end]
    "#{statement_date(row.period_start, dates, today)} – #{statement_date(row.period_end, dates, today)}"
  end

  private

  def statement_date(date, scope, today)
    date.strftime(scope.all? { |other| other.year == today.year } ? "%d/%m" : "%d/%m/%Y")
  end
end
