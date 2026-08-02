module Budgeting
  # "Consigo pagar o que já devo": the card debt already committed, month by
  # month, against the money on hand today. Optimistic by construction — no
  # future income and no future ordinary spending are counted — and the view
  # that shows it must say so.
  #
  # Committed debt is read straight out of statement derivation: attribution
  # already places every installment on a statement, and every statement already
  # knows when it falls due, so closed statements, statements still accumulating
  # and scheduled installments are one number per month. There is deliberately no
  # second way here of working out what is due when.
  #
  # Nothing is persisted; like every aggregate in this namespace it derives on
  # read, so an entry or a payment shows up on the next request.
  class Solvency
    Row = Data.define(:month, :committed_cents, :cumulative_cents)

    attr_reader :today, :current_month

    def initialize(today: Date.current)
      @today = today
      @current_month = today.beginning_of_month
    end

    def rows
      @rows ||= begin
        cumulative = 0
        horizon.map do |month|
          cumulative += committed_cents(month)
          Row.new(month:, committed_cents: committed_cents(month), cumulative_cents: cumulative)
        end
      end
    end

    def any? = rows.any?

    # Debt due before the current month and never paid. The horizon starts today,
    # so it has no row of its own and is folded into the first one — dropping it
    # would let the block report "covered" while a real debt sat outside the
    # picture. Exposed so the view can say the first row carries it.
    #
    # Netted as ONE sum over the past, never floored month by month: a statement
    # paid late is paid in a month that owes nothing itself, and flooring would
    # leave the original debt behind with nothing able to cancel it.
    def arrears_cents
      @arrears_cents ||=
        [ past_months.sum { |month| due_cents(month) - paid_cents(month) }, 0 ].max
    end

    # "Saldo atual" for the current month — income received minus debit and cash
    # spending, carried forward from previous months. One figure, compared
    # against the whole cumulative series; it is never recomputed per month,
    # because the block deliberately projects no income into the months ahead.
    def money_on_hand_cents
      @money_on_hand_cents ||= BalanceChain.current_balance(
        month: current_month, carried: BalanceChain.carried_into(month: current_month)
      )
    end

    # The first month whose cumulative debt passes the balance. A non-positive
    # balance therefore lands on the first row, which is the right answer: the
    # money is already gone.
    #
    # Memoized with a defined-check, not `||=`: a covered debt legitimately
    # returns nil, which `||=` would recompute on every call — the common case.
    def shortfall_row
      return @shortfall_row if defined?(@shortfall_row)
      @shortfall_row = rows.find { |row| row.cumulative_cents > money_on_hand_cents }
    end

    def covered? = shortfall_row.nil?

    # The difference AT that month — not the debt of the whole horizon.
    def shortfall_cents = shortfall_row && shortfall_row.cumulative_cents - money_on_hand_cents

    private

    def horizon
      @horizon ||= begin
        last = [ due_by_month.keys.max, current_month ].compact.max
        months = []
        cursor = current_month
        while cursor <= last
          months << cursor
          cursor = cursor >> 1
        end
        trim_settled_tail(months)
      end
    end

    # The horizon ends at the last month that still owes something. A quiet month
    # *inside* it stays listed as a zero row — a hole in the list would misread
    # as missing data.
    def trim_settled_tail(months)
      last_owed = months.rindex { |month| committed_cents(month).positive? }
      last_owed.nil? ? [] : months[0..last_owed]
    end

    def committed_cents(month) = committed_by_month[month]

    # Floored at zero: a month cannot owe a negative amount, and the surplus of
    # an overpayment is not carried anywhere. See the plan's recorded limitation
    # on paying ahead.
    def committed_by_month
      @committed_by_month ||= Hash.new do |cache, month|
        committed = due_cents(month) - paid_cents(month)
        committed += arrears_cents if month == current_month
        cache[month] = [ committed, 0 ].max
      end
    end

    def due_cents(month) = due_by_month.fetch(month, 0)

    def due_by_month
      @due_by_month ||= StatementSet.by_due_month.transform_values do |statements|
        statements.values.flatten.sum(&:amount_cents)
      end
    end

    def paid_cents(month) = paid_by_month.fetch(month, 0)

    # Payments are ordinary debit/cash expenses in the reserved category, with no
    # link to the statement they settle — the same filter
    # MonthSummary#statement_payments_cents uses, read for every month at once.
    # Filtered by `role`, never by a Category record: that row is renamable.
    def paid_by_month
      @paid_by_month ||=
        Expense.joins(:category)
               .where(categories: { role: "credit_card" }, payment_method: %w[debit cash])
               .group(:date).sum(:amount_cents)
               .each_with_object(Hash.new(0)) do |(date, cents), totals|
                 totals[date.beginning_of_month] += cents
               end
    end

    # Only months that actually saw a statement or a payment — the timeline's
    # start is irrelevant here, and reading it would tie this to Setting for
    # nothing.
    def past_months
      (due_by_month.keys | paid_by_month.keys).select { |month| month < current_month }
    end
  end
end
