require "rails_helper"

RSpec.describe "Home", type: :request do
  before { create_setting!; create_reserved_categories! }

  it "shows the saldo placeholder row and one row per category with its budget" do
    category = Category.create!(name: "mercado")
    Budget.create!(category:, month: Date.new(2026, 3, 1), amount_cents: 90_000)
    get root_path(month: "2026-03")
    expect(response.body).to include("saldo")
    expect(response.body).to include("mercado").and include("900,00")
    expect(response.body).to include("outros").and include("cartão de crédito")
    expect(response.body).to include(category_path(category, month: "2026-03"))
  end

  it "clamps navigation to the first month" do
    get root_path(month: "2025-01")
    expect(response.body).to include("03/2026")
  end

  it "shows the FAB with both actions" do
    get root_path
    expect(response.body).to include(new_expense_path).and include(new_income_path)
  end
end
