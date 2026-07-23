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
    # Anchored on word boundaries so a scope bug that counts the 10 installment
    # rows alongside the 1 standalone (11 total) can't satisfy this by rendering
    # "11 gasto avulsos" — plain #include?("1 gasto") would (Fix 2).
    expect(response.body).to match(/\b1 gasto avulso\b/)
    expect(response.body).to match(/\b1 compra parcelada\b/)
    expect(response.body).to include("Verde")
  end

  it "discloses that migrating re-files bills onto the destination card's statements (Fix 1)" do
    get new_card_migration_path(card)
    expect(response.body).to include("cartão de destino")
    expect(response.body).to include("fechamento e vencimento")
    expect(response.body).to include("podem cair em outro mês")
  end

  it "states the statement consequence and the counts in the migrate button's confirm (Fix 1)" do
    get new_card_migration_path(card)
    confirm = Capybara.string(response.body).find_button("Migrar e excluir cartão")["data-turbo-confirm"]
    expect(confirm).to match(/\b1 gasto avulso\b/)
    expect(confirm).to match(/\b1 compra parcelada\b/)
    expect(confirm).to include("cartão de destino")
    expect(confirm).to include("outro mês")
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
    purchase_id = InstallmentPurchase.find_by!(name: "sofá").id
    card_id = card.id

    post card_migration_path(card), params: { action_kind: "delete" }

    expect(Card.exists?(card_id)).to be false
    expect(Expense.where(name: "mercado")).to be_empty
    expect(InstallmentPurchase.where(name: "sofá")).to be_empty
    # The shipped code cascades to the purchase's 10 installment Expense rows via
    # `dependent: :destroy` off `installment_purchases.destroy_all` — a
    # `delete_all`-based implementation would skip the cascade and leave
    # these behind while still passing the assertions above (Fix 3).
    expect(Expense.where(installment_purchase_id: purchase_id)).to be_empty
    expect(Expense.where(card_id:)).to be_empty
  end

  it "requires a target card when migrating" do
    post card_migration_path(card), params: { action_kind: "migrate", target_card_id: "" }
    expect(response).to redirect_to(new_card_migration_path(card))
    expect(Card.exists?(card.id)).to be true
  end

  it "rejects a missing action_kind, leaving the card and its rows intact (Fix 4)" do
    post card_migration_path(card), params: {}
    expect(response).to redirect_to(new_card_migration_path(card))
    follow_redirect!
    expect(response.body).to include("Escolha o que fazer com os gastos.")
    expect(Card.exists?(card.id)).to be true
    expect(Expense.where(name: "mercado").count).to eq 1
    expect(InstallmentPurchase.where(name: "sofá").count).to eq 1
  end

  it "rejects an unexpected action_kind, leaving the card and its rows intact (Fix 4)" do
    post card_migration_path(card), params: { action_kind: "obliterate" }
    expect(response).to redirect_to(new_card_migration_path(card))
    follow_redirect!
    expect(response.body).to include("Escolha o que fazer com os gastos.")
    expect(Card.exists?(card.id)).to be true
    expect(Expense.where(name: "mercado").count).to eq 1
    expect(InstallmentPurchase.where(name: "sofá").count).to eq 1
  end

  it "rejects migrating a card to itself, leaving the card and its rows intact (Fix 4)" do
    post card_migration_path(card), params: { action_kind: "migrate", target_card_id: card.id }
    expect(response).to redirect_to(new_card_migration_path(card))
    follow_redirect!
    expect(response.body).to include("Escolha o cartão de destino.")
    expect(Card.exists?(card.id)).to be true
    expect(Expense.find_by!(name: "mercado").card).to eq card
    expect(InstallmentPurchase.find_by!(name: "sofá").card).to eq card
  end
end
