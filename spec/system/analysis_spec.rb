require "rails_helper"

RSpec.describe "Analysis", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }

  def seed_year
    Income.create!(name: "salário", amount_cents: 100_000, date: Date.new(2026, 3, 5))
    Expense.create!(name: "feira", amount_cents: 30_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 6))
  end

  # Every example keeps `visit` AND its assertions inside `travel_to`: the server
  # runs in this process, so letting the block close before a request lands would
  # have Rails answer it with the real current date.

  it "renders the four charts of the year (AC 2, 3, 6, 8)" do
    seed_year
    travel_to(Date.new(2026, 7, 1)) do
      visit analysis_path

      expect(page).to have_css("canvas", count: 4)
      expect(page).to have_content("Gastos por mês")
      expect(page).to have_content("Gastos por categoria")
      expect(page).to have_content("Lucro por mês")
      expect(page).to have_content("Gastos e saídas")
    end
  end

  it "switches the profit chart's mode without reloading the page (AC 6)" do
    seed_year
    travel_to(Date.new(2026, 7, 1)) do
      visit analysis_path
      # Survives only if the mode switch never navigates.
      page.execute_script("window.__stillHere = true")

      click_button "Ganhos − saídas"

      expect(find_button("Ganhos − saídas")["aria-pressed"]).to eq "true"
      expect(page.evaluate_script("window.__stillHere")).to be true
    end
  end

  it "reaches another year through the picker (AC 1)" do
    seed_year
    travel_to(Date.new(2027, 5, 10)) do
      visit analysis_path
      expect(page).to have_content("Nenhum lançamento em 2027")

      select "2026", from: "year"

      expect(page).to have_content("Gastos por mês")
    end
  end

  it "shows a message instead of empty axes for a year with no entries (AC 11)" do
    travel_to(Date.new(2026, 7, 1)) do
      visit analysis_path

      expect(page).to have_content("Nenhum lançamento em 2026")
      expect(page).to have_no_css("canvas")
    end
  end
end
