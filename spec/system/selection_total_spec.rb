require "rails_helper"

# User feedback: "a way to select a group of categories/payments to check the
# total amount of the selected items". Purely client-side — nothing is saved.
RSpec.describe "Selection total", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:casa) { Category.create!(name: "casa") }
  let(:lazer) { Category.create!(name: "lazer") }

  before do
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))
    Expense.create!(name: "feira", amount_cents: 90_000, payment_method: "debit", category: mercado, date: Date.new(2026, 3, 5))
    Expense.create!(name: "padaria", amount_cents: 1_050, payment_method: "cash", category: mercado, date: Date.new(2026, 3, 7))
    Expense.create!(name: "conta de luz", amount_cents: 30_000, payment_method: "debit", category: casa, date: Date.new(2026, 3, 6))
    Expense.create!(name: "cinema", amount_cents: 4_000, payment_method: "debit", category: lazer, date: Date.new(2026, 3, 8))
  end

  around { |example| travel_to(Date.new(2026, 3, 20)) { example.run } }

  it "adds up the spending of the categories ticked on Início, and clears" do
    visit root_path
    expect(page).to have_no_css("[data-selection-total-target='bar']", visible: true)

    check "selecionar mercado"
    check "selecionar casa"
    within("[data-selection-total-target='bar']") do
      expect(page).to have_content("2 selecionados")
      expect(page).to have_content("R$ 1.210,50")
    end

    uncheck "selecionar casa"
    within("[data-selection-total-target='bar']") do
      expect(page).to have_content("1 selecionado")
      expect(page).to have_content("R$ 910,50")
    end

    click_button "limpar seleção"
    expect(page).to have_no_css("[data-selection-total-target='bar']", visible: true)
    expect(page).to have_unchecked_field("selecionar mercado")
  end

  it "ticking a category does not open its page" do
    visit root_path
    check "selecionar mercado"
    expect(page).to have_current_path(root_path)
  end

  it "adds up the expenses ticked in the Gastos list" do
    visit expenses_path(month: "2026-03")

    check "selecionar feira"
    check "selecionar cinema"
    within("[data-selection-total-target='bar']") do
      expect(page).to have_content("2 selecionados")
      expect(page).to have_content("R$ 940,00")
    end
  end

  it "adds up the expenses ticked on a category's page" do
    visit category_path(mercado, month: "2026-03")

    check "selecionar feira"
    check "selecionar padaria"
    within("[data-selection-total-target='bar']") do
      expect(page).to have_content("R$ 910,50")
    end
  end
end
