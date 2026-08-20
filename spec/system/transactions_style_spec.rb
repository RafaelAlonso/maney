require "rails_helper"

# Proves the money-entry surfaces (Gastos + Ganhos lists, the shared expense
# row, and the income/expense forms) are on the w1 tokens: the list surface
# themes light↔dark, the styled empty states render with their exact copy, the
# row carries semantic classes and no legacy color utilities, and income amounts
# take the positive money colour while expense amounts stay neutral (Decision 1).
RSpec.describe "Transactions & entry styling", type: :system do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  def seed_expense(name: "mercado", cents: 24_000)
    Expense.create!(name:, amount_cents: cents, payment_method: "debit",
                    category: category("mercado"), date: Date.new(2026, 3, 6))
  end

  it "renders the Gastos list surface in both light and dark (AC 1)" do
    seed_expense

    set_prefers_color_scheme(:light)
    visit expenses_path(month: "2026-03")
    expect(background_of("ul")).to eq(rgb("#ffffff"))    # --color-surface, light

    click_button "Tema"                                   # flip to dark
    expect(page).to have_css("html.dark")
    expect(background_of("ul")).to eq(rgb("#131a22"))     # --color-surface, dark (--ink-900)
  end

  it "styles the expense row with semantic tokens and no legacy colours (AC 1)" do
    seed_expense
    visit expenses_path(month: "2026-03")

    within("ul") do
      expect(page).to have_css("a.text-accent", text: "editar")
      expect(page).to have_css(".text-money-expense", text: "excluir")
      expect(page).to have_css("p.text-muted", text: "R$ 240,00")
      expect(page).to have_no_css('[class*="gray-"]')
      expect(page).to have_no_css('[class*="blue-"]')
    end
  end

  it "shows a styled empty state for a month with no expenses (AC 2)" do
    visit expenses_path(month: "2026-03")

    expect(page).to have_css(".empty-state", text: "Nenhum gasto neste mês.")
  end

  def seed_income(name: "salário", cents: 500_000)
    Income.create!(name:, amount_cents: cents, date: Date.new(2026, 3, 5))
  end

  it "colours income amounts with the positive money token, derived rows neutral (AC 5, Decision 1)" do
    seed_income
    visit incomes_path(month: "2026-03")

    expect(page).to have_css("span.text-money-positive", text: "R$ 5.000,00")   # the income entry
    within("ul") do
      expect(page).to have_css("a.text-accent", text: "editar")
      expect(page).to have_css(".text-money-expense", text: "excluir")
      expect(page).to have_no_css('[class*="gray-"]')
      expect(page).to have_no_css('[class*="blue-"]')
    end
  end

  it "shows a styled empty state for a month with no incomes (AC 5)" do
    visit incomes_path(month: "2026-03")

    expect(page).to have_css(".empty-state", text: "Nenhum ganho lançado neste mês.")
  end

  it "renders the Ganhos list surface in both light and dark (AC 5)" do
    seed_income

    set_prefers_color_scheme(:light)
    visit incomes_path(month: "2026-03")
    expect(background_of("ul")).to eq(rgb("#ffffff"))

    click_button "Tema"
    expect(page).to have_css("html.dark")
    expect(background_of("ul")).to eq(rgb("#131a22"))
  end
end
