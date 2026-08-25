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

  # Cards offered when entering an expense: the active ones, plus this entry's
  # own card when it has since been archived. That exception is not cosmetic —
  # Expense#card_matches_method rejects a credit expense without a card, so
  # without the option the edit could not be saved at all. Only the entry's own
  # archived card is added: an edit must not be able to move an expense onto some
  # other retired card.
  #
  # This is the ONLY place in the app that filters cards by archived state.
  # Everywhere else — statements, month totals, charts, the forecast balance, the
  # committed debt — must keep seeing every card.
  def card_options_for(entry)
    cards = Card.active.order(:name).to_a
    current = Card.find_by(id: entry.card_id)
    cards << current if current&.archived? && cards.exclude?(current)
    cards.sort_by(&:name).map { |c| [ c.archived? ? "#{c.name} (arquivado)" : c.name, c.id ] }
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

  # The manual theme override, read server-side so the correct theme is in the
  # first byte we send (and in the service-worker-cached HTML) — no pre-paint
  # script, no flash. An absent or unknown cookie means "follow the device",
  # which CSS handles via prefers-color-scheme, so no class is stamped.
  def theme_html_class
    %w[dark light].include?(cookies[:theme]) ? cookies[:theme] : ""
  end

  # The toggle knob's starting side, decided server-side from the same cookie, so
  # it is already on the right side in the first byte of every navigation. Without
  # this the knob rendered on the left every time and the Stimulus `connect` slid
  # it across on each page switch — the flicker. Device-follow (no cookie) has no
  # server-known side, so it starts left and the controller positions it on
  # connect with the transition suppressed (theme_controller), which is instant.
  def theme_knob_translate_class
    cookies[:theme] == "dark" ? "translate-x-5" : "translate-x-0.5"
  end

  # The date a gasto row shows. A dated expense shows its day/month; an
  # installment parcel has no date of its own (its month comes from the schedule),
  # so it shows which parcel of the purchase it is instead of a fabricated date.
  def expense_date_label(expense)
    if expense.installment?
      "parcela #{expense.installment_number}/#{expense.installment_purchase.installments_count}"
    else
      expense.date.strftime("%d/%m")
    end
  end

  # A category's spending as a whole-number percentage of some total (its month's
  # income, or the month's total spending). Returns nil — rendered as "—" — when
  # the total is zero or absent, so an empty month never prints a fabricated 0%.
  def share_percent(part_cents, whole_cents)
    return nil if whole_cents.nil? || whole_cents <= 0
    (part_cents * 100.0 / whole_cents).round
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
    "vence #{statement_date(statement.effective_due, [ statement.effective_due ], today)}"
  end

  # The statement's purchase period: from the previous effective closing to the
  # day before this one. Same year rule as the due label, applied to both ends
  # together so the two dates always read in the same format.
  def statement_period_label(row, today: Date.current)
    dates = [ row.period_start, row.period_end ]
    "#{statement_date(row.period_start, dates, today)} – #{statement_date(row.period_end, dates, today)}"
  end

  # Which top-level destination the current screen belongs to — the shell marks
  # it active in the desktop nav, the mobile bottom bar and the "Mais" panel.
  # Matched on controller_name (every destination is a top-level controller), so
  # the Cartões statement/migration/archival screens all light up the Cartões tab.
  def nav_active?(*controllers)
    controllers.flatten.map(&:to_s).include?(controller_name)
  end

  # The primary destinations, in nav order, for the desktop top nav's left group;
  # the overflow controller decides which fit inline. Config is deliberately NOT
  # here — the shell pins it to the right of the bar (shared/_desktop_nav), so it
  # never folds into "Mais".
  def nav_destinations
    [
      { label: "Início",     path: root_path,          controllers: %w[home] },
      { label: "Gastos",     path: expenses_path,      controllers: %w[expenses] },
      { label: "Ganhos",     path: incomes_path,       controllers: %w[incomes] },
      { label: "Cartões",    path: cards_path,         controllers: %w[cards statements card_migrations card_archivals] },
      { label: "Categorias", path: categories_path,    controllers: %w[categories] },
      { label: "Análise",    path: analysis_path,      controllers: %w[analyses] }
    ]
  end

  private

  def statement_date(date, scope, today)
    date.strftime(scope.all? { |other| other.year == today.year } ? "%d/%m" : "%d/%m/%Y")
  end
end
