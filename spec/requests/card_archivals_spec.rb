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
end
