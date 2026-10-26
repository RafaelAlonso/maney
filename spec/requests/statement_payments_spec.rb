require "rails_helper"

# Frozen at 20/03/2026, like statements_spec: the statement closing 05/03 (due
# 12/03) is closed, the one closing 05/04 (due 13/04) is still open.
RSpec.describe "Statement payments", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 3, 20, 10, 0, 0)) { example.run } }

  before do
    create_setting!(initial_balance_cents: 100_000)
    create_reserved_categories!
  end

  let!(:card) { create_card!(name: "Azul", closing_day: 5, due_day: 12) }
  let!(:march_purchase) do
    Expense.create!(name: "tv", amount_cents: 50_000, date: Date.new(2026, 3, 4), payment_method: "credit",
                    card:, category: category("mercado"))
  end
  let(:march_closing) { "2026-03-05" }
  let(:itau) { Account.create!(name: "Itaú") }

  def html = Nokogiri::HTML(response.body)

  def pay(amount: "500,00", account: Account.primary, closing: march_closing, from: nil)
    post card_statement_payments_path(card, closing, from:),
         params: { statement_payment_entry: { account_id: account.id, amount:, date: "2026-03-20" } }
  end

  it "pre-fills the remaining amount and today's date" do
    get new_card_statement_payment_path(card, march_closing)
    expect(html.at("input[name='statement_payment_entry[amount]']")["value"]).to eq("500,00")
    expect(html.at("input[name='statement_payment_entry[date]']")["value"]).to eq("2026-03-20")

    pay(amount: "200,00")
    get new_card_statement_payment_path(card, march_closing)
    expect(html.at("input[name='statement_payment_entry[amount]']")["value"]).to eq("300,00")
  end

  it "pays a statement from an account: the account balance drops, the statement shows paga ✓" do
    pay(account: itau)

    expect(response).to redirect_to(card_statement_path(card, march_closing))
    payment = Expense.find_by!(statement_card: card)
    expect(payment).to have_attributes(name: "fatura Azul · vence 12/03", payment_method: "debit", account: itau,
                                       statement_closing_on: Date.new(2026, 3, 5))
    expect(payment.category).to be_credit_card
    expect(Budgeting::AccountBalances.new(month: Date.new(2026, 3, 1)).closing_cents(itau)).to eq(-50_000)
    follow_redirect!
    expect(response.body).to include("Pagamento lançado.").and include("paga ✓")
  end

  it "a partial payment shows falta R$ X and offers pagar again" do
    pay(amount: "200,00")

    get card_statements_path(card)

    expect(response.body).to include("falta R$ 300,00")
    expect(response.body).to include(new_card_statement_payment_path(card, march_closing))
  end

  it "pays from the carteira as dinheiro" do
    pay(account: Account.wallet)

    expect(Expense.find_by!(statement_card: card)).to have_attributes(payment_method: "cash", account: Account.wallet)
  end

  it "pays an open statement early" do
    Expense.create!(name: "fone", amount_cents: 10_000, date: Date.new(2026, 3, 6), payment_method: "credit",
                    card:, category: category("mercado"))

    pay(amount: "100,00", closing: "2026-04-05")

    get card_statement_path(card, "2026-04-05")
    expect(response.body).to include("paga ✓")
  end

  it "returns to Início when started there" do
    get new_card_statement_payment_path(card, march_closing, from: "home")
    expect(response.body).to include("from=home")

    pay(from: "home")

    expect(response).to redirect_to(root_path(month: "2026-03"))
  end

  it "edits and deletes a payment" do
    pay(amount: "200,00")
    payment = Expense.find_by!(statement_card: card)

    get edit_statement_payment_path(payment)
    expect(html.at("input[name='statement_payment_entry[amount]']")["value"]).to eq("200,00")

    patch statement_payment_path(payment),
          params: { statement_payment_entry: { account_id: Account.wallet.id, amount: "250,00", date: "2026-03-19" } }
    expect(payment.reload).to have_attributes(amount_cents: 25_000, account: Account.wallet, payment_method: "cash",
                                              date: Date.new(2026, 3, 19))
    expect(response).to redirect_to(card_statement_path(card, march_closing))

    delete statement_payment_path(payment)
    expect(Expense.exists?(payment.id)).to be false
    follow_redirect!
    expect(response.body).to include("Pagamento excluído.")
  end

  it "editar on a payment's Gastos row opens the payment form" do
    pay
    payment = Expense.find_by!(statement_card: card)

    get expenses_path(month: "2026-03")
    expect(response.body).to include(edit_statement_payment_path(payment))
    expect(response.body).not_to include(edit_expense_path(payment))

    get edit_expense_path(payment)
    expect(response).to redirect_to(edit_statement_payment_path(payment))
  end

  it "refuses another person's account and an unknown statement" do
    foreign = as(create_user!(email_address: "irma@example.com")) { create_setting!; Account.primary }
    pay(account: foreign)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("escolha a conta")
    expect(Expense.where(statement_card: card)).to be_empty

    get new_card_statement_payment_path(card, "2026-09-05")
    expect(response).to redirect_to(card_statements_path(card))
    follow_redirect!
    expect(response.body).to include("Fatura não encontrada.")

    post card_statement_payments_path(card, "not-a-date"),
         params: { statement_payment_entry: { account_id: Account.primary.id, amount: "1,00", date: "2026-03-20" } }
    expect(response).to redirect_to(card_statements_path(card))
  end

  it "a payment whose statement vanished still shows on its account page and Gastos, and its edit form still works" do
    pay
    payment = Expense.find_by!(statement_card: card)
    march_purchase.destroy!

    get account_path(Account.primary, month: "2026-03")
    expect(response.body).to include("fatura Azul · vence 12/03")
    get expenses_path(month: "2026-03")
    expect(response.body).to include("fatura Azul · vence 12/03")

    get edit_statement_payment_path(payment)
    expect(response).to have_http_status(:ok)
    patch statement_payment_path(payment),
          params: { statement_payment_entry: { account_id: Account.primary.id, amount: "450,00", date: "2026-03-20" } }
    expect(payment.reload.amount_cents).to eq(45_000)
    expect(response).to redirect_to(account_path(Account.primary, month: "2026-03"))
  end
end
