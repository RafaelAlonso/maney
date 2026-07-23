require "rails_helper"

RSpec.describe "Inline budget edit", type: :system do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  it "edits a category budget inline without leaving the month view (AC 8)" do
    mercado = Category.create!(name: "mercado")
    visit root_path(month: "2026-03")
    within "##{ActionView::RecordIdentifier.dom_id(mercado, :row)}" do
      find("[data-budget-edit-target='display']").click
      fill_in "budget_amount", with: "900,00"
      find("input[name='budget_amount']").send_keys(:return)
    end
    expect(page).to have_content("orçado R$ 900,00")
    expect(mercado.budgets.find_by(month: Date.new(2026, 3, 1)).amount_cents).to eq(90_000)
  end
end
