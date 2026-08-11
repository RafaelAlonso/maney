module Analysis
  # Base for the year charts. Each subclass emits a complete Chart.js config as a
  # Ruby hash, so the whole visual contract is assertable in RSpec instead of
  # being locked inside a canvas. The Stimulus side stays dumb.
  #
  # Values cross to JavaScript as reais, not cents: Chart.js formats the axis and
  # the tooltip with Intl.NumberFormat("pt-BR"), which yields the same
  # "-R$ 1.234,56" shape as ApplicationHelper#brl.
  #
  # The chrome in `base_options` follows the `dataviz` skill: recessive solid
  # hairline gridlines on the value axis only, no vertical grid, axis and legend
  # text in ink tokens rather than in the series colour, and one shared tooltip
  # listing every series at the hovered month.
  class BaseChart
    include MoneyValues

    MONTH_LABELS = MonthLabels::SHORT

    # The skill's bar spec: cap the mark instead of letting it fill the band, and
    # round the data-end while the baseline stays square.
    MAX_BAR_THICKNESS = 24
    BAR_END_RADIUS = 4

    def initialize(analysis, palette: Palette.new)
      @analysis = analysis
      @palette = palette
    end

    def title = raise NotImplementedError

    def to_config = raise NotImplementedError

    # A caveat rendered under the chart's title. Only the charts with no card
    # dimension answer this: they are labelled rather than filtered or hidden,
    # so a card-scoped year still reads as a whole.
    def note = nil

    # Whether to render `empty_message` in place of the canvas. An empty stacked
    # bar chart is a blank white box, which reads as broken rather than as "no
    # spending" — for a filtered card and for an unfiltered year alike.
    def empty? = false

    def empty_message
      return "Nenhum gasto em #{analysis.card.name} em #{analysis.year}." if analysis.filtered?
      "Nenhum gasto em #{analysis.year}."
    end

    private

    attr_reader :analysis, :palette

    def month_labels = MONTH_LABELS

    # The house bar spec, shared by every bar dataset in every chart:
    # `maxBarThickness` caps the mark instead of letting it fill the band, and
    # `pointStyle: "rect"` makes the legend swatch mirror the mark shape.
    # `BAR_END_RADIUS` is deliberately not included here — it must not reach
    # the stacked chart's inner segments, only the non-stacked charts merge it
    # in separately.
    def bar_defaults
      { maxBarThickness: MAX_BAR_THICKNESS, pointStyle: "rect" }
    end

    def values(series) = series.values_for_chart.map { |cents| reais(cents) }

    # The average is a flat line drawn across the active months only — it is
    # "my normal", and it has nothing to say about a month that never happened.
    # It is dashed and wears the ink colour, not a series colour: it is a
    # reference line rather than a ninth thing being measured.
    def average_dataset(series, label: "Média")
      average = reais(series.average_cents)
      {
        type: "line",
        label:,
        data: series.months.map { |month| series.active?(month) ? average : nil },
        borderColor: Palette::AVERAGE,
        borderDash: [ 6, 4 ],
        borderWidth: 2,
        pointRadius: 0,
        pointStyle: "line",
        fill: false
      }
    end

    def base_options
      {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "index", intersect: false },
        plugins: {
          legend: {
            display: true,
            position: "bottom",
            # `usePointStyle` makes each key mirror its mark — a rect for the
            # bars, a stroke for the average line — instead of drawing the
            # average's dashed border around a box, which read as a torn swatch.
            labels: { usePointStyle: true, boxWidth: 12, boxHeight: 12, color: Palette::MUTED_INK }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            border: { color: Palette::AXIS },
            # Twelve three-letter months on a 414 px phone sit close enough that
            # Chart.js tilts them to 45° by default. Held flat they stay far
            # easier to scan; `autoSkip: false` keeps all twelve, because a
            # month axis with holes in it misreads as missing data.
            ticks: { color: Palette::MUTED_INK, maxRotation: 0, autoSkip: false }
          },
          y: {
            beginAtZero: true,
            grid: { color: Palette::GRID, drawTicks: false },
            border: { display: false },
            ticks: { color: Palette::MUTED_INK }
          }
        }
      }
    end
  end
end
