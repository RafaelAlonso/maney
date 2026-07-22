require "rails_helper"

RSpec.describe "CardMigrations", type: :request do
  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }
  let!(:card) { create_card!(name: "Azul") }
  let!(:target) { create_card!(name: "Verde") }

  before do
    Expense.create!(name: "mercado", amount_cents: 10_000, payment_method: "credit",
                    card:, category: others, date: Date.new(2026, 3, 4))
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))
  end

  it "shows the counts and the destinations (AC 17)" do
    get new_card_migration_path(card)
    expect(response.body).to include("1 gasto").and include("1 compra parcelada")
    expect(response.body).to include("Verde")
  end

  it "migrates everything to another card and deletes the original (AC 17)" do
    post card_migration_path(card), params: { action_kind: "migrate", target_card_id: target.id }
    expect(Card.exists?(card.id)).to be false
    expect(Expense.find_by!(name: "mercado").card).to eq target
    purchase = InstallmentPurchase.find_by!(name: "sofá")
    expect(purchase.card).to eq target
    expect(purchase.expenses.pluck(:card_id).uniq).to eq [target.id]
  end

  it "deletes everything and the card (AC 17)" do
    post card_migration_path(card), params: { action_kind: "delete" }
    expect(Card.exists?(card.id)).to be false
    expect(Expense.where(name: "mercado")).to be_empty
    expect(InstallmentPurchase.where(name: "sofá")).to be_empty
  end

  it "requires a target card when migrating" do
    post card_migration_path(card), params: { action_kind: "migrate", target_card_id: "" }
    expect(response).to redirect_to(new_card_migration_path(card))
    expect(Card.exists?(card.id)).to be true
  end
end
