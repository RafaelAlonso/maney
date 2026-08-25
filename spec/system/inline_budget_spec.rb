require "rails_helper"

RSpec.describe "Inline budget edit", type: :system do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  # The budget is edited on the category's own dashboard now, not on the Início
  # card (which is read-only). Same click-to-edit, streamed back in place.
  it "edits a category budget from its dashboard without leaving the page (AC 8)" do
    mercado = Category.create!(name: "mercado")
    visit category_path(mercado, month: "2026-03")
    within "##{ActionView::RecordIdentifier.dom_id(mercado, :budget)}" do
      find("[data-budget-edit-target='display']").click
      fill_in "budget_amount", with: "900,00"
      find("input[name='budget_amount']").send_keys(:return)
    end
    expect(page).to have_content("orçado R$ 900,00")
    expect(mercado.budgets.find_by(month: Date.new(2026, 3, 1)).amount_cents).to eq(90_000)
  end

  it "keeps the edit input out of the way until the value is clicked" do
    mercado = Category.create!(name: "mercado")
    visit category_path(mercado, month: "2026-03")

    within "##{ActionView::RecordIdentifier.dom_id(mercado, :budget)}" do
      expect(page).to have_content("orçado R$ 0,00")
      expect(page).to have_no_field("budget_amount")

      find("[data-budget-edit-target='display']").click

      expect(page).to have_field("budget_amount")
    end
  end
end
