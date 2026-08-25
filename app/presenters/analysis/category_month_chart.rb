module Analysis
  # This month's spending, one bar per category, sorted most-expensive first, so
  # "where did the money go this month" reads at a glance on the Início screen.
  #
  # Not a BaseChart: BaseChart is a year of a single series with month labels and
  # an average line, none of which fit a one-month cross-category snapshot. It
  # takes only the cents-to-reais conversion from MoneyValues, like the
  # drill-down pie.
  #
  # The reserved credit-card category is left out on purpose: a credit purchase
  # already shows as a bar under its own category in the purchase month, so
  # plotting the statement-payment total too would count the same spending twice.
  # A category with nothing spent this month draws no bar — a zero-height bar is
  # noise, not information.
  class CategoryMonthChart
    include MoneyValues

    Bar = Data.define(:name, :amount_cents, :color)

    def initialize(summary:, categories:, palette: Palette.new)
      @summary = summary
      @categories = categories
      @palette = palette
    end

    def title = "Gastos por categoria em #{@summary.month.strftime('%m/%Y')}"

    # Largest first; the name breaks a tie so two categories matching to the cent
    # keep a stable order between requests. Each bar wears its category's own
    # theme-aware chart var, so a category keeps its hue across every screen and
    # the whole chart recolors live on the theme toggle.
    def bars
      @bars ||= @categories
                .reject(&:credit_card?)
                .map { |category| Bar.new(name: category.name, amount_cents: @summary.spent_cents(category),
                                          color: @palette.chart_var_for(category)) }
                .select { |bar| bar.amount_cents.positive? }
                .sort_by { |bar| [ -bar.amount_cents, bar.name ] }
    end

    def any? = bars.any?

    # Vertical bars with the value on the Y axis: chart_controller only money-formats
    # an axis it finds under `scales.y`, and its tooltip reads the value off `parsed.y`
    # — both of which a horizontal (indexAxis "y") bar would defeat. X labels are held
    # from tilting past 45°, which is where Chart.js would rotate several names on a phone.
    def to_config
      {
        type: "bar",
        data: {
          labels: bars.map(&:name),
          datasets: [ {
            label: "Gasto",
            data: bars.map { |bar| reais(bar.amount_cents) },
            backgroundColor: bars.map(&:color),
            borderRadius: 4,
            maxBarThickness: 28
          } ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } },
          scales: {
            x: {
              grid: { display: false },
              border: { color: Palette::AXIS },
              ticks: { color: Palette::MUTED_INK, maxRotation: 45, autoSkip: false }
            },
            y: {
              beginAtZero: true,
              grid: { color: Palette::GRID, drawTicks: false },
              border: { display: false },
              ticks: { color: Palette::MUTED_INK }
            }
          }
        }
      }
    end
  end
end
