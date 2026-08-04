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

    # This subclass is fed a Budgeting::CategoryYear, which has no card
    # dimension and answers no `filtered?`. It never needs the inherited
    # predicate either: categories/show.html.erb renders its own empty state
    # before shared/_chart is reached.
    def empty? = false

    # Reached only if a caller ignores `empty?`. The inherited empty_message
    # calls `analysis.filtered?`, which Budgeting::CategoryYear does not
    # answer and would raise; fall back to the year-only phrasing instead.
    def empty_message = "Nenhum gasto em #{analysis.year}."
  end
end
