module Analysis
  # AC 3: each month's spending split by category. The stack order is fixed for
  # the whole year — by year total, largest at the base — so a category holds the
  # same vertical position across all twelve bars. Which category *led a given
  # month* is answered by the tooltip, which sorts that month's own values
  # descending; on a 360 px phone there is no room for inline labels.
  class CategoryStackChart < BaseChart
    def title = "Gastos por categoria"

    def to_config
      {
        type: "bar",
        data: { labels: month_labels, datasets: analysis.categories.map { |category| dataset_for(category) } },
        options: stacked_options
      }
    end

    private

    # A month the category did not touch becomes `nil`, not zero: AC 5 asks for
    # the segment to be absent, and Chart.js draws nothing for a null.
    def dataset_for(category)
      series = analysis.spending_by_category.fetch(category)
      {
        type: "bar",
        label: category.name,
        backgroundColor: palette.color_for(category),
        data: series.months.map { |month| series.active?(month) && series.cents(month) != 0 ? reais(series.cents(month)) : nil }
      }
    end

    def stacked_options
      options = base_options
      options.merge(
        scales: { x: options[:scales][:x].merge(stacked: true), y: options[:scales][:y].merge(stacked: true) },
        plugins: options[:plugins].merge(tooltip: { itemSort: "desc" })
      )
    end
  end
end
