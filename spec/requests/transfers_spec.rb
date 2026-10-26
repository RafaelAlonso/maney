require "rails_helper"

RSpec.describe "Transfers", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 4, 20, 10, 0, 0)) { example.run } }

  before do
    create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 100_000)
    create_reserved_categories!
  end

  let(:april) { Date.new(2026, 4, 1) }
  let(:itau) { Account.create!(name: "Itaú") }

  def html = Nokogiri::HTML(response.body)

  def post_transfer(**attrs)
    post transfers_path, params: { transfer: { from_account_id: Account.primary.id, to_account_id: Account.wallet.id,
                                               amount: "50,00", date: "2026-04-10", note: "" }.merge(attrs) }
  end

  it "creates a saque: Conta principal → Carteira moves both balances, not the total, and no category or Ganhos changes" do
    Income.create!(name: "salário", amount_cents: 50_000, date: Date.new(2026, 4, 5))
    summary = -> { Budgeting::MonthSummary.new(month: april) }
    before_figures = [ summary.call.current_balance_cents, summary.call.incomes_total_cents,
                       Category.all.map { |category| summary.call.spent_cents(category) } ]

    post_transfer(note: "saque")

    expect(response).to redirect_to(account_path(Account.primary, month: "2026-04"))
    follow_redirect!
    expect(response.body).to include("Transferência lançada.").and include("saque")
    after_figures = [ summary.call.current_balance_cents, summary.call.incomes_total_cents,
                      Category.all.map { |category| summary.call.spent_cents(category) } ]
    expect(after_figures).to eq(before_figures)
    balances = Budgeting::AccountBalances.new(month: april)
    expect(balances.closing_cents(Account.wallet)).to eq(5_000)
    expect(balances.closing_cents(Account.primary)).to eq(145_000)
    expect(Expense.count).to eq(0)
  end

  it "pre-fills the origin from the account page" do
    get account_path(itau, month: "2026-04")
    expect(response.body).to include(new_transfer_path(from_account_id: itau.id))

    get new_transfer_path(from_account_id: itau.id)

    expect(html.at("select[name='transfer[from_account_id]'] option[selected]")&.attr("value")).to eq(itau.id.to_s)
    expect(html.at("input[name='transfer[date]']")["value"]).to eq("2026-04-20")
  end

  it "redirects back to the origin account's page for the transfer's month" do
    post_transfer(from_account_id: itau.id, to_account_id: Account.primary.id, date: "2026-03-15")

    expect(response).to redirect_to(account_path(itau, month: "2026-03"))
  end

  it "edits and deletes a transfer" do
    transfer = Transfer.create!(from_account: Account.primary, to_account: itau, amount_cents: 1_000, date: Date.new(2026, 4, 2))
    get account_path(itau, month: "2026-04")
    expect(response.body).to include(edit_transfer_path(transfer))

    get edit_transfer_path(transfer)
    expect(response.body).to include("10,00")

    patch transfer_path(transfer), params: { transfer: { from_account_id: Account.primary.id, to_account_id: itau.id,
                                                         amount: "20,00", date: "2026-04-03", note: "reserva" } }
    expect(transfer.reload.amount_cents).to eq(2_000)
    expect(transfer.note).to eq("reserva")
    follow_redirect!
    expect(response.body).to include("Transferência atualizada.")

    delete transfer_path(transfer)
    expect(Transfer.exists?(transfer.id)).to be false
    expect(response).to redirect_to(account_path(Account.primary, month: "2026-04"))
    follow_redirect!
    expect(response.body).to include("Transferência excluída.")
  end

  it "refuses the same account on both sides, and another person's account id" do
    post_transfer(to_account_id: Account.primary.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("deve ser diferente da origem")

    foreign = as(create_user!(email_address: "irma@example.com")) { create_setting!; Account.primary }
    post_transfer(to_account_id: foreign.id)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Transfer.count).to eq(0)
  end

  it "re-renders with the typed amount when it doesn't parse" do
    post_transfer(amount: "abc")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido").and include('value="abc"')
    expect(response.body).not_to include("Amount cents")
  end
end
