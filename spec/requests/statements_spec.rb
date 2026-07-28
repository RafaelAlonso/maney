require "rails_helper"

# Frozen at 20/03/2026: March is already closed and April is still open, so both
# blocks of the list have content and the labels don't depend on the real clock.
RSpec.describe "Statements", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!; create_reserved_categories! }
  around { |example| travel_to(Time.zone.local(2026, 3, 20, 10, 0, 0)) { example.run } }

  let!(:card) { create_card!(name: "Azul", closing_day: 5, due_day: 12) }

  def credit_expense(amount, date, name: "compra", on: card)
    Expense.create!(name:, amount_cents: amount, date:, payment_method: "credit",
                    card: on, category: category("mercado"))
  end

  it "lists the card's statements with period, effective due date and total (AC 1)" do
    credit_expense(20_000, Date.new(2026, 3, 4))
    credit_expense(5_000, Date.new(2026, 3, 6))

    get card_statements_path(card)

    expect(response.body).to include("Azul").and include("Em aberto").and include("Fechadas")
    expect(response.body).to include("vence 12/03").and include("vence 13/04")
    expect(response.body).to include("R$ 200,00").and include("R$ 50,00")
    expect(response.body).to include("05/03 – 02/04")
  end

  it "always shows the effective due date, never the nominal one (AC 5)" do
    credit_expense(5_000, Date.new(2026, 3, 6))

    get card_statements_path(card)

    expect(response.body).to include("vence 13/04")
    expect(response.body).not_to include("vence 12/04")
  end

  it "shows a friendly empty state for a card with no expense (AC 4)" do
    get card_statements_path(card)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nenhuma fatura ainda")
    expect(response.body).not_to include("Em aberto")
  end

  it "lists only its own statements when two cards are due in the same month" do
    roxo = create_card!(name: "Roxo", closing_day: 5, due_day: 12)
    credit_expense(20_000, Date.new(2026, 3, 4))
    credit_expense(7_000, Date.new(2026, 3, 4), on: roxo)

    get card_statements_path(roxo)

    expect(response.body).to include("R$ 70,00")
    expect(response.body).not_to include("R$ 200,00")
  end

  it "links to the card's statements from the card list" do
    get cards_path

    expect(response.body).to include("faturas").and include(card_statements_path(card))
  end

  it "shows the statement's expenses, whose amounts sum to the displayed total (AC 2)" do
    credit_expense(20_000, Date.new(2026, 3, 6), name: "mercado")
    InstallmentPurchase.create!(name: "sofá", total_cents: 60_000, installments_count: 3,
                                date: Date.new(2026, 3, 6), card:, category: category("casa"))

    # 2026-04-05 is the April statement's NOMINAL closing date — its effective
    # one is 03/04, because 05/04/2026 is a Sunday.
    get card_statement_path(card, "2026-04-05")

    expect(response.body).to include("mercado").and include("sofá 1/3")
    expect(response.body).to include("vence 13/04").and include("compras de 05/03 – 02/04")
    expect(response.body).to include("R$ 200,00")  # each of the two items
    expect(response.body).to include("R$ 400,00")  # the total
  end

  it "does not repeat the statement label on the rows of its own detail" do
    credit_expense(20_000, Date.new(2026, 3, 6), name: "mercado")

    get card_statement_path(card, "2026-04-05")

    expect(response.body.scan("vence 13/04").size).to eq 1
  end

  it "redirects with the neutral notice when the id is unknown or malformed" do
    credit_expense(5_000, Date.new(2026, 3, 6))

    get card_statement_path(card, "2026-09-05")
    expect(response).to redirect_to(root_path)

    get card_statement_path(card, "banana")
    expect(response).to redirect_to(root_path)
  end
end
