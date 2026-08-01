module Budgeting
  # The twelve months of a year plus the mask of which of them actually
  # happened: on or after the user's first month, and not in the future.
  #
  # That mask is the whole of the year screen's AC 9 and AC 10 and of the
  # drill-down's AC 7 — a month outside it is *no data*, never a zero. It lives
  # here rather than in YearAnalysis because two screens now ask the same
  # question of the same year, and a second copy of this rule is exactly the
  # divergence the drill-down story calls a defect.
  class YearCalendar
    def initialize(year:, today: Date.current)
      @year = year
      @today = today
    end

    def months
      @months ||= (1..12).map { |month| Date.new(@year, month, 1) }
    end

    def active_months
      @active_months ||= begin
        first = Setting.instance&.first_month
        last = @today.beginning_of_month
        first.nil? ? [] : months.select { |month| month >= first && month <= last }
      end
    end

    def active?(month) = active_months.include?(month)
  end
end
