require "rails_helper"

RSpec.describe "Analysis chart theming", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }

  # First canvas on the page is always "Gastos por mês"; dataset 0 is its bar
  # series, whose backgroundColor is the single resolved --chart-1 color.
  def spending_bar_color
    page.evaluate_script(<<~JS)
      window.Chart.getChart(document.querySelector('canvas')).data.datasets[0].backgroundColor
    JS
  end

  it "recolors the charts on a live theme toggle and keeps the selected profit mode (AC 1)" do
    Income.create!(name: "salário", amount_cents: 100_000, date: Date.new(2026, 3, 5))
    Expense.create!(name: "feira", amount_cents: 30_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 6))

    travel_to(Date.new(2026, 7, 1)) do
      set_prefers_color_scheme(:light)
      visit analysis_path

      expect(page).to have_css("canvas", count: 4)
      expect(spending_bar_color).to eq "#2a78d6"          # --chart-1, light

      # Select a non-default profit mode before flipping the theme.
      click_button "Ganhos − saídas"
      expect(find_button("Ganhos − saídas")["aria-pressed"]).to eq "true"

      find("button[aria-label='Alternar tema']").click                                  # flip to dark
      expect(page).to have_css("html.dark")                # sync point: CSS + theme:change fired

      expect(spending_bar_color).to eq "#3987e5"           # --chart-1, dark — recolored live
      expect(find_button("Ganhos − saídas")["aria-pressed"]).to eq "true" # mode survived recolor
    end
  end
end
