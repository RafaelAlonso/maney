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
    MONTH_LABELS = %w[jan fev mar abr mai jun jul ago set out nov dez].freeze

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

    private

    attr_reader :analysis, :palette

    def month_labels = MONTH_LABELS

    def reais(cents) = cents.nil? ? nil : (cents / 100.0).round(2)

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
            labels: { boxWidth: 12, boxHeight: 12, color: Palette::MUTED_INK }
          }
        },
        scales: {
          x: {
            grid: { display: false },
            border: { color: Palette::AXIS },
            ticks: { color: Palette::MUTED_INK }
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
