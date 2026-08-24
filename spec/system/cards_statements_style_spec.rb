require "rails_helper"

# Proves the card/statement surfaces are on the w1 tokens and recolor with the
# theme, and that the styled empty state and semantic statement total render —
# the visible payoff of the restyle, in the real browser.
RSpec.describe "Cards & statements styling", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  it "renders the card list surface in both light and dark (AC 1)" do
    create_card!(name: "Azul", closing_day: 5, due_day: 12)

    set_prefers_color_scheme(:light)
    visit cards_path
    expect(background_of("ul")).to eq(rgb("#ffffff"))   # --color-surface, light

    find("button[aria-label='Alternar tema']").click                                  # flip to dark
    expect(page).to have_css("html.dark")
    expect(background_of("ul")).to eq(rgb("#131a22"))    # --color-surface, dark (--ink-900)
  end

  it "shows a styled empty state for a card with no statements (AC 3)" do
    create_card!(name: "Azul", closing_day: 5, due_day: 12)

    visit card_statements_path(Card.find_by!(name: "Azul"))

    expect(page).to have_css(".card .empty-state", text: "Nenhuma fatura ainda")
  end

  it "shows the statement-detail total in the expense money color (AC 4)" do
    travel_to(Time.zone.local(2026, 3, 20, 10, 0, 0)) do
      card = create_card!(name: "Azul", closing_day: 5, due_day: 12)
      Expense.create!(name: "mercado", amount_cents: 20_000, date: Date.new(2026, 3, 6),
                      payment_method: "credit", card:, category: category("mercado"))

      visit card_statement_path(card, "2026-04-05")

      expect(page).to have_css("p.text-money-expense", text: "R$ 200,00")
    end
  end
end
