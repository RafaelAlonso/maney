module Budgeting
  # Card date rules: overflow of a nonexistent day and adjustment to a business
  # day (closing moves back, due date moves forward). Holidays out of scope.
  module Calendar
    module_function

    def nominal_date(year, month, day)
      Date.new(year, month, 1) + (day - 1)
    end

    def effective_closing(nominal)
      date = nominal
      date -= 1 while date.saturday? || date.sunday?
      date
    end

    def effective_due(nominal)
      date = nominal
      date += 1 while date.saturday? || date.sunday?
      date
    end
  end
end
