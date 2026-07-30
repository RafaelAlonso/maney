module Analysis
  # AC 8: what was consumed against what actually left the account, month by
  # month. Grouped bars, never stacked and never summed — the gap between the
  # two is the credit being carried forward, and that only reads if they sit
  # side by side.
  class SpendingVsOutflowChart < BaseChart
    def title = "Gastos e saídas"

    def to_config
      {
        type: "bar",
        data: {
          labels: month_labels,
          datasets: [
            { type: "bar", label: "Gastos", data: values(analysis.spending), backgroundColor: Palette::PRIMARY },
            { type: "bar", label: "Saídas", data: values(analysis.cash_outflow), backgroundColor: Palette::OUTFLOW }
          ]
        },
        options: base_options
      }
    end
  end
end
