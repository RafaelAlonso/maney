require "rails_helper"

RSpec.describe "Category drill-down chart theming", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }

  # The breakdown pie is the second canvas on the drill-down (year chart first).
  # dataset 0's backgroundColor is the array of resolved slice colours; index 1
  # is a color-mix() slice, so it must resolve to an rgb() string, not a token.
  def pie_slice_color
    page.evaluate_script(<<~JS)
      window.Chart.getChart(document.querySelectorAll('canvas')[1]).data.datasets[0].backgroundColor[1]
    JS
  end

  it "recolors the breakdown pie live on a theme toggle (AC 3)" do
    Expense.create!(name: "mercado extra", amount_cents: 48_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 6))
    Expense.create!(name: "padaria", amount_cents: 22_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 8))

    travel_to(Date.new(2026, 3, 20)) do
      set_prefers_color_scheme(:light)
      visit category_path(mercado, month: "2026-03")

      expect(page).to have_css("canvas", count: 2)
      light = pie_slice_color
      # color-mix() was evaluated to a concrete colour, not left as the raw
      # token expression. Headless Chrome serializes a resolved color-mix()
      # as either rgb()/rgba() or, when the mix needs more precision than an
      # 8-bit channel, the color(srgb ...) function — never the literal
      # "color-mix(...)"/"var(...)" source string.
      expect(light).to match(/\A(rgba?|color)\(/)

      click_button "Tema"                  # flip to dark
      expect(page).to have_css("html.dark") # sync point: CSS + theme:change fired

      expect(pie_slice_color).not_to eq light # recolored live against the dark surface
    end
  end
end
