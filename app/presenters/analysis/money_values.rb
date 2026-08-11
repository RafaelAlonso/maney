module Analysis
  # Cents to reais, the one conversion every chart makes on its way to Chart.js.
  #
  # It is a module rather than a method on BaseChart because not every chart is
  # a year chart: the drill-down pie needs this and nothing else BaseChart owns,
  # and inheriting for it left the pie with a constructor it could not call.
  module MoneyValues
    private

    # `nil` is a gap, and must stay one: a month with no data is not zero.
    def reais(cents) = cents.nil? ? nil : (cents / 100.0).round(2)
  end
end
