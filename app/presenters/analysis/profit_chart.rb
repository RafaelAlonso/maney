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

    DEFAULT_MODE = "spending"

    def title = "Lucro por mês"

    def note = analysis.filtered? ? "Cobre todos os cartões" : nil

    def mode_labels = MODE_LABELS.to_a

    def modes
      @modes ||= {
        "spending" => [ vs_spending ],
        "outflow" => [ vs_outflow ],
        # Both series stay sign-readable (AC 7), but they must also be
        # distinguishable from each other: "Ganhos − gastos" stays filled,
        # "Ganhos − saídas" renders as an outline (transparent fill, sign-
        # coloured border) so fill-vs-outline separates the two on top of
        # colour alone.
        "both" => [ vs_spending, profit_dataset(consolidated.profit_vs_outflow, MODE_LABELS.fetch("outflow"), outline: true) ]
      }
    end

    def to_config
      { type: "bar", data: { labels: month_labels, datasets: modes.fetch(DEFAULT_MODE) }, options: base_options }
    end

    private

    # Everything this chart plots comes from the unfiltered twin: `spending` is
    # narrowed on a filtered analysis, and this chart is labelled rather than
    # narrowed. Reading `analysis` directly here is the regression this exists
    # to prevent.
    def consolidated = analysis.consolidated

    def vs_spending = profit_dataset(consolidated.profit_vs_spending, MODE_LABELS.fetch("spending"))

    def vs_outflow = profit_dataset(consolidated.profit_vs_outflow, MODE_LABELS.fetch("outflow"))

    # The colour is resolved per bar here rather than in a Chart.js callback:
    # callbacks cannot cross JSON, and a per-bar array is exactly what Chart.js
    # accepts for backgroundColor/borderColor.
    #
    # `outline:` is used only in the "both" mode, where two series share the
    # same sign palette and would otherwise be indistinguishable — both stayed
    # filled and identically green in every inactive month (backgroundColor[0]
    # is the legend swatch source, and January is `nil` for both series).
    # "Ganhos − saídas" renders instead as a transparent-fill, sign-coloured
    # outline, so fill-vs-outline separates the two on top of colour alone.
    def profit_dataset(series, label, outline: false)
      data = values(series)
      colors = data.map { |value| value.nil? || value >= 0 ? Palette::POSITIVE : Palette::NEGATIVE }

      dataset = { type: "bar", label:, data:, borderRadius: BAR_END_RADIUS, **bar_defaults }
      if outline
        dataset.merge!(backgroundColor: "transparent", borderColor: colors, borderWidth: 2)
      else
        dataset[:backgroundColor] = colors
      end
      dataset
    end
  end
end
