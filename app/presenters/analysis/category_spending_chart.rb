module Analysis
  # AC 1: one category's monthly totals across the year, with its own average
  # line. This *is* the year screen's SpendingChart — same bars, same dashed
  # average, same axis chrome — because SpendingChart reads nothing but
  # `analysis.spending`, and Budgeting::CategoryYear answers that. Subclassing
  # for the title is the entire difference, which is what makes a drift between
  # the two screens impossible rather than merely tested against.
  #
  # The title carries the year because this screen has no year picker: the year
  # comes from the month the user navigated to, so it has to be stated somewhere.
  class CategorySpendingChart < SpendingChart
    def title = "Gastos por mês em #{analysis.year}"
  end
end
