require "rails_helper"

RSpec.describe "Accounts", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 4, 20, 10, 0, 0)) { example.run } }

  before do
    create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 100_000)
    create_reserved_categories!
  end

  let(:itau) { Account.create!(name: "Itaú") }

  def html = Nokogiri::HTML(response.body)

  it "lists accounts with their balance for the current month, reserved ones without archive/delete" do
    Income.create!(name: "salário", amount_cents: 50_000, date: Date.new(2026, 4, 5), account: itau)

    get accounts_path

    expect(response.body).to include("Conta principal").and include("Carteira").and include("Itaú")
    expect(response.body).to include("R$ 1.000,00").and include("R$ 500,00")
    expect(html.css("form[action='#{account_archival_path(Account.primary)}']")).to be_empty
    expect(html.css("form[action='#{account_path(Account.wallet)}']")).to be_empty
    expect(html.css("form[action='#{account_archival_path(itau)}']")).not_to be_empty
  end

  it "shows an account's month: opening balance, movements with running balance, closing balance" do
    Income.create!(name: "salário", amount_cents: 50_000, date: Date.new(2026, 3, 5))
    Income.create!(name: "freela", amount_cents: 20_000, date: Date.new(2026, 4, 5))
    Expense.create!(name: "feira", amount_cents: 5_000, date: Date.new(2026, 4, 6), payment_method: "debit",
                    category: category("mercado"))

    get account_path(Account.primary, month: "2026-04")

    expect(response.body).to include("saldo anterior").and include("R$ 1.500,00")
    expect(response.body).to include("freela").and include("feira")
    expect(response.body).to include("R$ 1.700,00") # after freela
    expect(response.body).to include("R$ 1.650,00") # closing
  end

  it "navigates months on the account page" do
    get account_path(Account.primary, month: "2026-04")

    expect(response.body).to include(account_path(Account.primary, month: "2026-03"))
    expect(response.body).to include(account_path(Account.primary, month: "2026-05"))
  end

  it "archives and reactivates an ordinary account; an archived account still counts in the total" do
    Income.create!(name: "salário", amount_cents: 50_000, date: Date.new(2026, 4, 5), account: itau)

    post account_archival_path(itau)
    expect(response).to redirect_to(accounts_path)
    expect(itau.reload).to be_archived
    follow_redirect!
    expect(response.body).to include("Conta arquivada.")
    expect(response.body).to include("R$ 1.500,00") # total, Itaú's 500 included

    delete account_archival_path(itau)
    expect(itau.reload).not_to be_archived
  end

  it "refuses to archive a reserved account" do
    post account_archival_path(Account.wallet)

    expect(Account.wallet).not_to be_archived
    follow_redirect!
    expect(response.body).to include("não pode ser arquivada")
  end

  it "deletes an account with no history and refuses one with history" do
    empty = Account.create!(name: "Inter")
    delete account_path(empty)
    expect(Account.exists?(empty.id)).to be false

    Income.create!(name: "salário", amount_cents: 50_000, date: Date.new(2026, 4, 5), account: itau)
    delete account_path(itau)
    expect(Account.exists?(itau.id)).to be true
    follow_redirect!
    expect(response.body).to include("Conta com lançamentos não pode ser excluída — arquive-a.")
  end

  it "opens a new account with today's balance from another account" do
    get new_account_path
    expect(response.body).to include("Quanto tem nela hoje (R$)").and include("Vindo de")

    post accounts_path, params: { account_opening: { name: "Itaú", amount: "200,00",
                                                     source_account_id: Account.primary.id } }

    account = Account.find_by!(name: "Itaú")
    expect(response).to redirect_to(account_path(account))
    expect(Budgeting::AccountBalances.new(month: Date.new(2026, 4, 1)).closing_cents(account)).to eq(20_000)
  end

  it "re-renders the new form when the amount doesn't parse" do
    post accounts_path, params: { account_opening: { name: "Itaú", amount: "abc",
                                                     source_account_id: Account.primary.id } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido").and include('value="abc"')
  end

  it "renames an account, reserved ones included" do
    patch account_path(Account.primary), params: { account: { name: "Nubank" } }

    expect(Account.primary.name).to eq("Nubank")
    expect(response).to redirect_to(account_path(Account.primary))
  end

  it "is reachable from Mais" do
    get root_path

    expect(html.css("aside a[href='#{accounts_path}']").map(&:text)).to include("Contas")
  end

  it "another person's account is not found" do
    foreign = as(create_user!(email_address: "irma@example.com")) { create_setting!; Account.primary }

    get account_path(foreign)

    expect(response).to redirect_to(root_path)
  end
end
