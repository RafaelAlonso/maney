module Analysis
  # AC 6 and AC 7: monthly profit, switchable between income minus spending,
  # income minus cash outflow, and both together. All three modes are shipped to
  # the browser at once so switching is instant and does not reload the page —
  # the gap between the two measures is the credit being carried forward, and it
  # is read by flipping back and forth.
  class ProfitChart < BaseChart
    MODE_LABELS = {
      "spending" => "Ganhos − gastos",
      "outflow" => "Ganhos − saídas",
      "both" => "Os dois"
    }.freeze

    def title = "Lucro por mês"

    def mode_labels = MODE_LABELS.to_a

    def modes
      @modes ||= {
        "spending" => [ vs_spending ],
        "outflow" => [ vs_outflow ],
        "both" => [ vs_spending, vs_outflow ]
      }
    end

    def to_config
      { type: "bar", data: { labels: month_labels, datasets: modes.fetch("spending") }, options: base_options }
    end

    private

    def vs_spending = profit_dataset(analysis.profit_vs_spending, MODE_LABELS.fetch("spending"))

    def vs_outflow = profit_dataset(analysis.profit_vs_outflow, MODE_LABELS.fetch("outflow"))

    # The colour is resolved per bar here rather than in a Chart.js callback:
    # callbacks cannot cross JSON, and a per-bar array is exactly what Chart.js
    # accepts for backgroundColor.
    def profit_dataset(series, label)
      data = values(series)
      {
        type: "bar",
        label:,
        data:,
        backgroundColor: data.map { |value| value.nil? || value >= 0 ? Palette::POSITIVE : Palette::NEGATIVE }
      }
    end
  end
end
