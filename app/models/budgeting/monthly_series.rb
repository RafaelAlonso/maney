module Budgeting
  # Twelve monthly amounts plus the mask of which of those months actually
  # happened. The mask is the whole point: a month before the user's first month
  # or after the current one is not zero spending, it is *no data*, and the two
  # must never be confused — a zero bar reads as "I spent nothing", a gap reads
  # as "this month is not mine to talk about".
  #
  # The average is the story's "my normal": it covers active months only. An
  # active month where nothing was spent counts as a real zero, because that
  # month did happen.
  class MonthlySeries
    attr_reader :months

    def initialize(months:, active_months:, amounts: {})
      @months = months
      @active_months = active_months.to_set
      @amounts = amounts
    end

    def active?(month) = @active_months.include?(month)

    def cents(month) = @amounts.fetch(month, 0)

    # What the charts plot: `nil` for an inactive month, so Chart.js draws a gap
    # rather than a bar sitting on the axis.
    def values_for_chart = months.map { |month| active?(month) ? cents(month) : nil }

    # Integer division: the result is cents, and a fractional cent has no meaning
    # on a chart axis that is read to the nearest real.
    def average_cents
      values = active_values
      return 0 if values.empty?
      values.sum / values.size
    end

    def total_cents = active_values.sum

    def any? = active_values.any? { |cents| cents != 0 }

    def -(other)
      self.class.new(months:, active_months: @active_months,
                     amounts: months.index_with { |month| cents(month) - other.cents(month) })
    end

    private

    def active_values = months.select { |month| active?(month) }.map { |month| cents(month) }
  end
end
