require "rails_helper"

RSpec.describe "Card archivals", type: :request do
  before { create_setting!; create_reserved_categories! }

  it "archives a card and says so (AC 1)" do
    card = create_card!(name: "Azul")

    post card_archival_path(card)

    expect(response).to redirect_to(cards_path)
    expect(card.reload).to be_archived
    follow_redirect!
    expect(response.body).to include("Cartão arquivado.")
  end

  it "reactivates an archived card (AC 3)" do
    card = create_card!(name: "Azul")
    card.archive!

    delete card_archival_path(card)

    expect(response).to redirect_to(cards_path)
    expect(card.reload).not_to be_archived
    follow_redirect!
    expect(response.body).to include("Cartão reativado.")
  end

  # The story is explicit that this option was rejected: a cancelled card
  # usually still owes, and refusing to archive it is the one thing archiving
  # exists to avoid.
  it "archives a card that still owes an unpaid statement" do
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card:, category: category("mercado"))

    post card_archival_path(card)

    expect(card.reload).to be_archived
    expect(response).to redirect_to(cards_path)
  end

  describe "the Cartões list" do
    it "keeps an archived card listed, marked, offering reactivation (AC 1)" do
      card = create_card!(name: "Azul")
      card.archive!

      get cards_path

      expect(response.body).to include("Azul").and include("arquivado")
      expect(response.body).to include("reativar")
      expect(response.body).to include(card_statements_path(card))
      # Renaming and rescheduling only make sense for a card being spent on;
      # reactivate first. Reactivating is lossless, so nothing is stranded.
      expect(response.body).not_to include(edit_card_path(card))
    end

    it "offers archiving, editing and deleting on an active card" do
      card = create_card!(name: "Azul")

      get cards_path

      expect(response.body).to include("arquivar")
      expect(response.body).to include(edit_card_path(card))
      expect(response.body).not_to include("reativar")
    end

    it "restores the active actions after reactivation (AC 3)" do
      card = create_card!(name: "Azul")
      card.archive!

      delete card_archival_path(card)
      follow_redirect!

      expect(response.body).to include("arquivar").and include(edit_card_path(card))
      expect(response.body).not_to include("arquivado")
    end
  end

  describe "deletion, unchanged by archiving (AC 9)" do
    it "still routes an archived card with expenses through the migration flow" do
      card = create_card!(name: "Azul")
      Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                      payment_method: "credit", card:, category: category("mercado"))
      card.archive!

      delete card_path(card)

      expect(response).to redirect_to(new_card_migration_path(card))
      expect(Card.exists?(card.id)).to be true
    end

    it "still deletes an archived card that has no expenses" do
      card = create_card!(name: "Azul")
      card.archive!

      delete card_path(card)

      expect(response).to redirect_to(cards_path)
      expect(Card.exists?(card.id)).to be false
    end

    # Migrating expenses onto an archived card moves HISTORY, not spending, so
    # an archived card stays a legitimate migration target.
    it "still offers an archived card as a migration target" do
      source = create_card!(name: "Azul")
      target = create_card!(name: "Preto")
      target.archive!
      Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                      payment_method: "credit", card: source, category: category("mercado"))

      get new_card_migration_path(source)

      expect(response.body).to include("Preto")
    end
  end
end
