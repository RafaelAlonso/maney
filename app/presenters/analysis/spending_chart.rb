module Analysis
  # AC 2: each month's total spending by purchase month, with an average line
  # over the months that have data.
  class SpendingChart < BaseChart
    def title = "Gastos por mês"

    def to_config
      series = analysis.spending
      {
        type: "bar",
        data: {
          labels: month_labels,
          datasets: [
            {
              type: "bar",
              label: "Gastos",
              data: values(series),
              backgroundColor: Palette::PRIMARY,
              borderRadius: BAR_END_RADIUS,
              **bar_defaults
            },
            average_dataset(series)
          ]
        },
        options: base_options
      }
    end
  end
end
