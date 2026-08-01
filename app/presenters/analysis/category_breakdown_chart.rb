module Analysis
  # AC 3: the selected month broken down by expense, each slice carrying its
  # share of *the category's* month total — never of the month's overall
  # spending.
  #
  # Fed by the same MonthEntries collection the list below it renders, so the
  # pie can never disagree with the list; and MonthEntries applies the same
  # competence rule as CompetenceSpending, so it can never disagree with the bar
  # chart above it either.
  #
  # Subclasses BaseChart for `reais` and the shared conventions, but overrides
  # the constructor — there is no YearAnalysis here — and builds its own options,
  # because BaseChart#base_options describes a value axis a pie does not have.
  class CategoryBreakdownChart < BaseChart
    Slice = Data.define(:name, :amount_cents, :color, :share_percent)

    def initialize(expenses:, category:, month:, palette: Palette.new)
      @expenses = expenses
      @category = category
      @month = month
      @palette = palette
    end

    def title = "Composição de #{@month.strftime('%m/%Y')}"

    def any? = @expenses.any?

    def total_cents = @total_cents ||= @expenses.sum(&:amount_cents)

    # Largest first, so the ramp's darkest shade lands on the expense that made
    # the month. The name breaks a tie, because two expenses matching to the cent
    # must not reorder between requests.
    def slices
      @slices ||= begin
        ordered = @expenses.sort_by { |expense| [ -expense.amount_cents, expense.name ] }
        colors = palette.shades_for(@category, count: ordered.size)
        ordered.each_with_index.map do |expense, index|
          Slice.new(name: expense.name, amount_cents: expense.amount_cents, color: colors[index],
                    share_percent: (expense.amount_cents * 100.0 / total_cents).round)
        end
      end
    end

    # No `scales` key: a pie has no value axis, and chart_controller only adds
    # its money formatting where one exists. The legend is off because the HTML
    # list beneath the canvas carries every name, amount and share as selectable
    # text — which AC 3 asks for, and which the palette notes require wherever
    # colour carries meaning.
    def to_config
      {
        type: "pie",
        data: {
          labels: slices.map(&:name),
          datasets: [ {
            data: slices.map { |slice| reais(slice.amount_cents) },
            backgroundColor: slices.map(&:color),
            borderColor: "#ffffff",
            borderWidth: 2
          } ]
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          plugins: { legend: { display: false } }
        }
      }
    end
  end
end
