module Analysis
  # AC 8: what was consumed against what actually left the account, month by
  # month. Grouped bars, never stacked and never summed — the gap between the
  # two is the credit being carried forward, and that only reads if they sit
  # side by side.
  class SpendingVsOutflowChart < BaseChart
    def title = "Gastos e saídas"

    def note = analysis.filtered? ? "Cobre todos os cartões" : nil

    def to_config
      {
        type: "bar",
        data: {
          labels: month_labels,
          datasets: [
            { type: "bar", label: "Gastos", data: values(consolidated.spending), backgroundColor: Palette::PRIMARY,
              borderRadius: BAR_END_RADIUS, **bar_defaults },
            { type: "bar", label: "Saídas", data: values(consolidated.cash_outflow), backgroundColor: Palette::OUTFLOW,
              borderRadius: BAR_END_RADIUS, **bar_defaults }
          ]
        },
        options: base_options
      }
    end

    private

    # Everything this chart plots comes from the unfiltered twin: `spending` is
    # narrowed on a filtered analysis, and this chart is labelled rather than
    # narrowed. Reading `analysis` directly here is the regression this exists
    # to prevent.
    def consolidated = analysis.consolidated
  end
end
