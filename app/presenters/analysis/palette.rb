module Analysis
  # Colours for the year charts. Categories have no colour column and none is
  # added: the palette index is the category's position in `Category.order(:name)`,
  # which is stable across years and across screens. Ordering by name rather than
  # by spending is the point — a category's colour must not change because a
  # different year was selected, or because it had a quiet month.
  #
  # The hex values are the `dataviz` skill's validated reference palette, checked
  # with its validator against this app's chart surface (white cards on
  # `bg-gray-50`). The app has no dark mode, so only the light steps are carried.
  #
  #   node scripts/validate_palette.js "<CATEGORY_COLORS>" --mode light --surface "#ffffff"
  #   → lightness band, chroma floor, CVD separation and normal-vision floor all PASS
  #     (worst adjacent CVD ΔE 9.1, worst adjacent normal-vision ΔE 19.6)
  #
  # The slot *order* is the colourblind-safety mechanism, not decoration: only
  # neighbouring slots are checked for separation, so reordering this list
  # invalidates the run above. Three slots (aqua, yellow, magenta) sit below 3:1
  # against white, which the validator flags as needing relief — a category chart
  # using them owes the reader the value in text (legend + tooltip readout), never
  # colour alone.
  #
  # The chart *roles* below (PRIMARY..MUTED_INK) are CSS-var tokens, not hex:
  # they resolve client-side (chart_controller.js#resolveVars) against the
  # `--chart-*` custom properties defined per theme in
  # app/assets/tailwind/application.css, so a chart recolors live on the theme
  # toggle. CATEGORY_COLORS and shades_for stay hex — the drill-down ramp
  # (Categories story) is not themed yet.
  class Palette
    PRIMARY = "var(--chart-1)".freeze     # categorical slot 1 — spending
    OUTFLOW = "var(--chart-2)".freeze     # categorical slot 2 — cash outflow
    AVERAGE = "var(--chart-average)".freeze # secondary ink: the average is chrome, not a series
    POSITIVE = "var(--chart-positive)".freeze # status "good"
    NEGATIVE = "var(--chart-negative)".freeze # status "critical"

    # Chart chrome, one step off the surface so it stays recessive.
    GRID = "var(--chart-grid)".freeze
    AXIS = "var(--chart-axis)".freeze
    MUTED_INK = "var(--chart-label)".freeze

    CATEGORY_COLORS = %w[
      #2a78d6 #eb6834 #1baf7a #eda100 #e87ba4 #008300 #4a3aa7 #e34948
    ].freeze

    # How far the lightest slice may be mixed toward the card's white. Capped
    # well short of 1.0 so the last slice of a twenty-expense month still
    # carries enough of the category's hue to be seen against #ffffff.
    WHITE_MIX_CAP = 0.6

    def initialize
      @order = Category.order(:name).pluck(:id)
    end

    def color_for(category)
      CATEGORY_COLORS[slot_index(category)]
    end

    # The categorical chart var for this category's slot — the theme-aware
    # sibling of color_for, used by the stacked chart. Same slot, so a category
    # keeps its hue across the stack chart and (later) the drill-down.
    def chart_var_for(category)
      "var(--chart-#{slot_index(category) + 1})"
    end

    # A sequential ramp of one category's colour, darkest first — the drill-down
    # pie's slices are expenses, not categories, so they cannot take categorical
    # hues without a hue meaning two different things in two screens. Ordered
    # largest-first by the caller, so shade encodes rank and explains itself.
    def shades_for(category, count:)
      return [] if count <= 0
      base = color_for(category)
      return [ base ] if count == 1
      (0...count).map { |index| mix_with_white(base, WHITE_MIX_CAP * index / (count - 1)) }
    end

    private

    def slot_index(category) = (@order.index(category.id) || 0) % CATEGORY_COLORS.size

    def mix_with_white(hex, fraction)
      channels = hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) }
      format("#%02x%02x%02x", *channels.map { |channel| (channel + (255 - channel) * fraction).round })
    end
  end
end
