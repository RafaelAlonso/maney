module Budgeting
  # (purchase date, card validity window) -> statement. Deterministic: the
  # statement is the first whose effective closing is later than the purchase
  # date — a purchase on the effective closing date goes to the next one.
  module StatementAttribution
    module_function

    # `memo:` is an optional Budgeting::ScheduleMemo, threaded down so a whole
    # derivation reads the card's validity windows once instead of per day. It
    # changes nothing about the result; omitted, every lookup queries.
    def statement_for(card:, date:, memo: nil)
      schedule = Schedule.for(card:, date:, memo:)
      cycle = (date << 1).beginning_of_month
      loop do
        statement = Statement.new(card:, cycle:, schedule:, memo:)
        return statement if statement.effective_closing > date
        cycle = cycle >> 1
      end
    end

    # Start of the statement window containing `date`: the smallest day that
    # still falls in the same statement as `date`. Defined by the attribution
    # function itself, not by walking the chain with succ: succ re-resolves the
    # validity window at each closing, so the chain can move backward (closing on
    # the 31st -> the 1st crosses the month boundary) and any traversal based on
    # it misses the boundary. This way the boundary is, by construction, the same
    # one statement_for sees.
    def window_start(card:, date:, memo: nil)
      earliest = Schedule.windows(card:, memo:).first&.valid_from
      raise ArgumentError, "card #{card.id} has no schedule" if earliest.nil?
      return earliest if date <= earliest

      target = statement_for(card:, date:, memo:)
      day = date
      day -= 1 while day > earliest && statement_for(card:, date: day - 1, memo:) == target
      day
    end

    # Installment k: the purchase's statement advanced by (k - first installment
    # created) statements — a per-statement sequence, with no date of its own.
    def statement_for_installment(purchase:, number:, memo: nil)
      statement = statement_for(card: purchase.card, date: purchase.date, memo:)
      (number - purchase.first_installment).times { statement = statement.succ }
      statement
    end
  end
end
