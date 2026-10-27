module Budgeting
  # Bill payments read against the statements they pay. A payment is a
  # débito/dinheiro expense in the reserved credit-card category
  # (Expense.statement_payments); a *linked* one also names its statement by card
  # + nominal closing, resolved here the way CardStatements#find does — same card
  # and nominal closing, earliest nominal due when a schedule change left two.
  #
  # Unlinked payments (everything entered before the link existed) and linked
  # ones whose statement no longer resolves (its purchases were all deleted, its
  # card migrated) keep counting by their own date, exactly as before. A linked
  # payment that resolves settles debt in its statement's due month — so paying
  # early never shows "paga ✓" next to a shortfall for the same bill.
  class StatementPayments
    def initialize(by_due_month: StatementSet.by_due_month)
      @by_due_month = by_due_month
    end

    def statement_for(expense)
      return nil unless expense.statement_payment?
      index[[ expense.statement_card_id, expense.statement_closing_on ]]
    end

    def paid_cents(statement) = paid_by_statement.fetch(statement, 0)

    # Overpaying is allowed; what is left never goes negative.
    def remaining_cents(statement, amount_cents) = [ amount_cents - paid_cents(statement), 0 ].max

    # :untracked for statements due before tracking started — the old unlinked
    # payments can't be matched to them, so they get no status at all.
    def status(statement, amount_cents)
      return :untracked if statement.effective_due < Setting.instance.statements_tracked_from

      paid = paid_cents(statement)
      return :unpaid if paid.zero?
      paid >= amount_cents ? :paid : :partial
    end

    def settled_by_month
      @settled_by_month ||= payments.each_with_object(Hash.new(0)) do |payment, totals|
        statement = statement_for(payment)
        month = statement ? statement.effective_due.beginning_of_month : payment.date.beginning_of_month
        totals[month] += payment.amount_cents
      end
    end

    # Resolved linked payments, by their own date.
    def linked_paid_in(month) = paid_in(month).sum { |payment| statement_for(payment) ? payment.amount_cents : 0 }

    # Everything else, by its own date.
    def unlinked_paid_in(month) = paid_in(month).sum { |payment| statement_for(payment) ? 0 : payment.amount_cents }

    private

    def payments
      @payments ||= Expense.statement_payments.to_a
    end

    def paid_in(month)
      range = month.beginning_of_month.all_month
      payments.select { |payment| range.cover?(payment.date) }
    end

    def paid_by_statement
      @paid_by_statement ||= payments.each_with_object(Hash.new(0)) do |payment, totals|
        statement = statement_for(payment)
        totals[statement] += payment.amount_cents if statement
      end
    end

    def index
      @index ||= @by_due_month.values.flat_map(&:keys)
                              .group_by { |statement| [ statement.card.id, statement.nominal_closing ] }
                              .transform_values { |statements| statements.min_by(&:nominal_due) }
    end
  end
end
