require "rails_helper"

RSpec.describe "Category drill-down", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }

  def seed_month
    Expense.create!(name: "mercado extra", amount_cents: 48_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 6))
    Expense.create!(name: "padaria", amount_cents: 22_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 8))
  end

  # Every example keeps `visit` AND its assertions inside `travel_to`: the server
  # runs in this process, so letting the block close before a request lands would
  # have Rails answer it with the real current date.

  it "opens a category from the month screen and draws both charts (AC 1, AC 3)" do
    seed_month
    travel_to(Date.new(2026, 3, 20)) do
      visit root_path
      click_on "mercado"

      expect(page).to have_content("Gastos por mês em 2026")
      expect(page).to have_content("Composição de 03/2026")
      expect(page).to have_content("69%")

      # A <canvas> renders identically from ERB whether Chart.js drew into it or
      # threw on import, so the assertions above cannot see a JS failure.
      # Chart.getChart returns the live instance (or undefined) — this is the
      # only check here that fails if a config is malformed.
      expect(page.evaluate_script(<<~JS)).to eq 2
        Array.from(document.querySelectorAll('canvas'))
             .filter(c => window.Chart.getChart(c)).length
      JS
    end
  end

  it "keeps the year chart when the month has nothing to break down (AC 4)" do
    seed_month
    travel_to(Date.new(2026, 5, 20)) do
      visit category_path(mercado, month: "2026-05")

      expect(page).to have_content("Nenhum gasto neste mês.")
      expect(page).to have_css("canvas", count: 1)
      expect(page.evaluate_script(<<~JS)).to eq 1
        Array.from(document.querySelectorAll('canvas'))
             .filter(c => window.Chart.getChart(c)).length
      JS
    end
  end
end
