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

  # The edit input used to render visible on every page load, next to the value
  # it was supposed to replace: `form_with` silently drops a top-level `hidden:`
  # option, and the form's `display: inline` class beat `[hidden] { display:
  # none }` anyway. The month view — the product's central screen — showed a row
  # of loose text boxes, costing a line per category on a phone.
  it "keeps the edit input out of the way until the value is clicked" do
    mercado = Category.create!(name: "mercado")
    visit root_path(month: "2026-03")

    within "##{ActionView::RecordIdentifier.dom_id(mercado, :row)}" do
      expect(page).to have_content("orçado R$ 0,00")
      expect(page).to have_no_field("budget_amount")

      find("[data-budget-edit-target='display']").click

      expect(page).to have_field("budget_amount")
    end
  end
end
