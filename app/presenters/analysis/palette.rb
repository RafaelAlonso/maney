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
  # toggle. CATEGORY_COLORS/color_for stay hex (they define the categorical hues
  # chart_var_for indexes into); shades_for now emits color-mix() tokens that
  # resolve against --color-surface client-side, so the drill-down ramp themes too.
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
    #
    # Emits CSS tokens, not hex: the darkest slice is the category's own chart
    # var, and each lighter slice mixes that var toward the current surface via
    # color-mix(). chart_controller.js#resolveVars evaluates the mix against the
    # live theme, so a slice recolors on the theme toggle. The base weight steps
    # down from 100% to (1 - WHITE_MIX_CAP)*100 = 40%, capped short of the surface
    # so even the last slice of a twenty-expense month keeps enough hue to be seen.
    def shades_for(category, count:)
      return [] if count <= 0
      base = chart_var_for(category)
      return [ base ] if count == 1
      (0...count).map do |index|
        next base if index.zero?
        weight = ((1 - WHITE_MIX_CAP * index / (count - 1)) * 100).round
        "color-mix(in srgb, #{base} #{weight}%, var(--color-surface))"
      end
    end

    private

    def slot_index(category) = (@order.index(category.id) || 0) % CATEGORY_COLORS.size
  end
end
