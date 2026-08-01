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

  # A card's days as the lists show them. A due day that is not after the closing
  # day is perfectly valid — the engine rolls the due date into the following
  # month, which is how many real cards work — but on screen "fecha dia 20 ·
  # vence dia 12" reads as a typo, and nothing distinguished a deliberate
  # next-month due date from a slip of the keyboard. The tail says which one the
  # user is looking at.
  def card_days_label(schedule)
    days = "fecha dia #{schedule.closing_day} · vence dia #{schedule.due_day}"
    schedule.due_day > schedule.closing_day ? days : "#{days} (vence no mês seguinte)"
  end

  # Rails' `pluralize` inflects only the last word of the phrase, which is right
  # for English ("3 loose expenses") and wrong for Portuguese, where the plural
  # agrees across the whole noun phrase: `pluralize(3, "gasto avulso")` gives
  # "3 gasto avulsos", not "3 gastos avulsos". Both forms are spelled out here
  # instead of derived — the app only needs a handful, and any rule we invented
  # would be wrong on the next irregular one.
  def pt_pluralize(count, singular, plural)
    "#{count} #{count == 1 ? singular : plural}"
  end

  # Single source for the payment-method labels — used by the expense form
  # (radios) and the expense row (`expenses/_row`, reused by categories#show).
  # Repeating this hash in every view is how Task 6 found the original form: the
  # same translation transcribed three times.
  PAYMENT_METHOD_LABELS = { "credit" => "crédito", "debit" => "débito", "cash" => "dinheiro" }.freeze

  def payment_method_labels = PAYMENT_METHOD_LABELS

  def payment_method_label(method) = PAYMENT_METHOD_LABELS[method]

  # A month as the Análise section writes it: "ago" this year, "jan/2028" beyond
  # it. The solvency horizon can run two years out, where a bare "jan" would read
  # as this coming January.
  def month_label(month, today: Date.current) = Analysis::MonthLabels.for(month, today:)

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
