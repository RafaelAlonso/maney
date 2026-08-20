require "rails_helper"

RSpec.describe "Budgets (inline edit)", type: :request do
  let(:march) { Date.new(2026, 3, 1) }
  before { create_setting!(first_month: march); create_reserved_categories! }

  it "creates a Budget and streams the row and hero (AC 8)" do
    mercado = Category.create!(name: "mercado")
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    post budgets_path, params: { category_id: mercado.id, month: "2026-03", budget_amount: "900,00" },
         as: :turbo_stream
    expect(Budget.find_by(category: mercado, month: march).amount_cents).to eq(90_000)
    expect(response.media_type).to eq Mime[:turbo_stream]
    # The dashboard now streams the balance hero (id="hero") in place of the old
    # two-row "balances" panel after a budget save.
    expect(response.body).to include("hero").and include(ActionView::RecordIdentifier.dom_id(mercado, :row))
  end

  it "upserts an existing Budget so the edited value prevails (AC 8)" do
    mercado = Category.create!(name: "mercado")
    Budget.create!(category: mercado, month: march, amount_cents: 50_000)
    post budgets_path, params: { category_id: mercado.id, month: "2026-03", budget_amount: "1.200,00" },
         as: :turbo_stream
    expect(Budget.where(category: mercado, month: march).count).to eq(1)
    expect(Budget.find_by(category: mercado, month: march).amount_cents).to eq(120_000)
  end

  it "rejects an unparseable amount with 422 and an error" do
    mercado = Category.create!(name: "mercado")
    post budgets_path, params: { category_id: mercado.id, month: "2026-03", budget_amount: "abc" },
         as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
  end

  it "rejects a manual budget on the credit-card category (422)" do
    post budgets_path, params: { category_id: credit_card_category.id, month: "2026-03", budget_amount: "100,00" },
         as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Budget.where(category: credit_card_category)).to be_empty
  end
end
