module Analysis
  # The section's month names, in one place. The year charts label a fixed
  # calendar year and the solvency table runs across years — two callers, and
  # transcribing twelve Portuguese month names twice is how they drift apart.
  module MonthLabels
    SHORT = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

    module_function

    def short(month) = SHORT[month.month - 1]

    # The year appears only when it differs from today's, so a horizon crossing
    # the rollover can't be read as this year's, while the everyday label stays
    # short. Same rule ApplicationHelper#statement_date applies to statement
    # dates.
    def for(month, today: Date.current)
      month.year == today.year ? short(month) : "#{short(month)}/#{month.year}"
    end
  end
end
