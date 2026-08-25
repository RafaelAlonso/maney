require "rails_helper"

RSpec.describe "Início dashboard", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:casa) { Category.create!(name: "casa") }

  def seed
    Income.create!(name: "salário", amount_cents: 200_000, date: Date.new(2026, 3, 1))
    Expense.create!(name: "feira", amount_cents: 90_000, payment_method: "debit", category: mercado, date: Date.new(2026, 3, 5))
    Expense.create!(name: "conta", amount_cents: 30_000, payment_method: "debit", category: casa, date: Date.new(2026, 3, 6))
  end

  it "draws the per-category bar chart as a live Chart.js instance (item 1)" do
    seed
    travel_to(Date.new(2026, 3, 20)) do
      Capybara.using_wait_time(5) do
        visit root_path

        expect(page).to have_content("Gastos por categoria em 03/2026")
        expect(page.evaluate_script(<<~JS)).to eq 1
          Array.from(document.querySelectorAll('canvas'))
               .filter(c => window.Chart.getChart(c)).length
        JS
      end
    end
  end

  it "toggles the percentage reading on the cards through the switch (item 2)" do
    seed
    travel_to(Date.new(2026, 3, 20)) do
      Capybara.using_wait_time(5) do
        visit root_path

        row = "##{ActionView::RecordIdentifier.dom_id(mercado, :row)}"
        # Default reading is share of the month's spending: mercado is 90.000 of 120.000 = 75%.
        within(row) { expect(page).to have_content("75% dos gastos") }

        click_button "% ganhos"

        # After the switch, the income reading shows: 90.000 of 200.000 = 45%.
        within(row) { expect(page).to have_content("45% dos ganhos") }
      end
    end
  end
end
