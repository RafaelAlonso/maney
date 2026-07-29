require "rails_helper"

RSpec.describe "Categories", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }

  it "creates a category with the month's budget (AC 2)" do
    post categories_path, params: { category: { name: "mercado", budget_amount: "900,00" }, month: "2026-03" }
    category = Category.find_by!(name: "mercado")
    expect(Budget.find_by(category:, month: Date.new(2026, 3, 1)).amount_cents).to eq 90_000
  end

  it "lists categories with the month's budget (AC 2)" do
    category = Category.create!(name: "mercado")
    Budget.create!(category:, month: Date.new(2026, 3, 1), amount_cents: 90_000)
    get categories_path(month: "2026-03")
    expect(response.body).to include("mercado").and include("900,00")
  end

  it "updates name and budget" do
    category = Category.create!(name: "mercado")
    patch category_path(category), params: { category: { name: "feira", budget_amount: "500,00" }, month: "2026-03" }
    expect(category.reload.name).to eq "feira"
    expect(Budget.find_by(category:, month: Date.new(2026, 3, 1)).amount_cents).to eq 50_000
  end

  it "shows the category's expenses in the month, all methods (home drill-down)" do
    card = create_card!
    category = Category.create!(name: "mercado")
    Expense.create!(name: "feira", amount_cents: 2_000, payment_method: "cash", category:, date: Date.new(2026, 3, 5))
    Expense.create!(name: "compra grande", amount_cents: 20_000, payment_method: "credit", card:, category:, date: Date.new(2026, 3, 4))
    get category_path(category, month: "2026-03")
    expect(response.body).to include("feira").and include("compra grande")
  end

  it "deleting a category with expenses moves them to the default (AC 15)" do
    card = create_card!
    category = Category.create!(name: "padaria")
    expense = Expense.create!(name: "pão", amount_cents: 500, payment_method: "cash", category:, date: Date.new(2026, 3, 5))
    purchase = InstallmentPurchase.create!(name: "cesta", total_cents: 10_000, installments_count: 2,
                                           card:, category:, date: Date.new(2026, 3, 5))
    delete category_path(category)
    expect(Category.exists?(category.id)).to be false
    expect(expense.reload.category).to eq others
    expect(purchase.reload.category).to eq others
    # Each installment has its own denormalized category_id — reassigning the
    # InstallmentPurchase doesn't drag the installments along. It's only the
    # unrestricted update_all on @category.expenses that today sweeps them all too.
    expect(purchase.expenses.reload.map(&:category)).to all(eq(others))
  end

  it "refuses to delete reserved categories (AC 15)" do
    delete category_path(others)
    expect(Category.exists?(others.id)).to be true
    expect(response).to redirect_to(categories_path(month: Date.current.strftime("%Y-%m")))
  end

  it "does not render a delete button for reserved categories (AC 15)" do
    get categories_path
    expect(response.body).not_to include(%(action="#{category_path(others)}"))
  end

  it "renaming the default category is allowed (AC 12)" do
    patch category_path(others), params: { category: { name: "geral" }, month: "2026-03" }
    expect(others.reload.name).to eq "geral"
  end

  # Point 1 of the revised brief: a budget that doesn't parse (or is negative)
  # must not be swallowed silently — it needs 422 + visible error + no partial
  # write (category and budget are born together or not at all).
  it "does not create a category when the budget is unparseable (422, no partial write)" do
    post categories_path, params: { category: { name: "mercado", budget_amount: "abc" }, month: "2026-03" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
    expect(Category.exists?(name: "mercado")).to be false
  end

  it "does not apply the name change when the budget is unparseable on update" do
    category = Category.create!(name: "mercado")
    patch category_path(category), params: { category: { name: "feira", budget_amount: "abc" }, month: "2026-03" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
    expect(category.reload.name).to eq "mercado"
  end

  it "creates a category with a blank budget (no budget for the month)" do
    post categories_path, params: { category: { name: "lazer", budget_amount: "" }, month: "2026-03" }
    category = Category.find_by!(name: "lazer")
    expect(Budget.find_by(category:, month: Date.new(2026, 3, 1))).to be_nil
  end

  it "surfaces the model's error for a negative budget (422, no partial write)" do
    post categories_path, params: { category: { name: "mercado", budget_amount: "-10,00" }, month: "2026-03" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Category.exists?(name: "mercado")).to be false
  end

  # Fix 1: the form never shows the budget field for the reserved credit-card
  # category, but a forged/direct submit needs the same treatment as the other
  # categories — blank is a no-op, present is a 422 from the model's error.
  it "a blank budget on the credit-card category stays a no-op success" do
    cc = credit_card_category
    patch category_path(cc), params: { category: { name: cc.name, budget_amount: "" }, month: "2026-03" }
    expect(response).to redirect_to(categories_path(month: "2026-03"))
    expect(Budget.where(category: cc).count).to eq 0
  end

  it "rejects a present budget on the credit-card category (422, model's message, no write)" do
    cc = credit_card_category
    patch category_path(cc), params: { category: { name: cc.name, budget_amount: "100,00" }, month: "2026-03" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("cartão de crédito não aceita orçado manual")
    expect(Budget.where(category: cc).count).to eq 0
  end

  it "labels credit expenses with their statement in the category drill-down (AC 3)" do
    travel_to(Time.zone.local(2026, 3, 20, 10, 0, 0)) do
      card = create_card!(name: "Azul", closing_day: 5, due_day: 12)
      mercado = Category.create!(name: "mercado")
      Expense.create!(name: "feira", amount_cents: 20_000, payment_method: "credit",
                      category: mercado, card:, date: Date.new(2026, 3, 6))

      get category_path(mercado, month: "2026-03")

      expect(response.body).to include("vence 13/04")
      expect(response.body).to include(card_statement_path(card, "2026-04-05"))
    end
  end
end
