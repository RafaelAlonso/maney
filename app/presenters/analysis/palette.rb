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
  class Palette
    PRIMARY = "#2a78d6".freeze   # categorical slot 1 — spending
    OUTFLOW = "#eb6834".freeze   # categorical slot 2 — cash outflow
    AVERAGE = "#52514e".freeze   # secondary ink: the average is chrome, not a series
    POSITIVE = "#0ca30c".freeze  # status "good"
    NEGATIVE = "#d03b3b".freeze  # status "critical"

    # Chart chrome, one step off the surface so it stays recessive.
    GRID = "#e1e0d9".freeze
    AXIS = "#c3c2b7".freeze
    MUTED_INK = "#898781".freeze

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
      index = @order.index(category.id) || 0
      CATEGORY_COLORS[index % CATEGORY_COLORS.size]
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

    def mix_with_white(hex, fraction)
      channels = hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) }
      format("#%02x%02x%02x", *channels.map { |channel| (channel + (255 - channel) * fraction).round })
    end
  end
end
