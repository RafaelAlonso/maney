module Budgeting
  # Splits an installment purchase into cents: always by the total number of
  # installments, with the leftover cents on the first installment created
  # (rule from story w1).
  module InstallmentSplit
    Part = Data.define(:number, :amount_cents)

    module_function

    def call(total_cents:, count:, first: 1)
      base = total_cents / count
      remainder = total_cents - base * count
      (first..count).map do |number|
        Part.new(number:, amount_cents: base + (number == first ? remainder : 0))
      end
    end
  end
end
