require "rails_helper"

RSpec.describe AccountOpening do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 5, 20, 10, 0, 0)) { example.run } }

  before do
    create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 100_000)
  end

  let(:may) { Date.new(2026, 5, 1) }

  def balances = Budgeting::AccountBalances.new(month: may)

  it "opens an account with today's balance taken from Conta principal, leaving saldo atual unchanged" do
    before_total = Budgeting::MonthSummary.new(month: may).current_balance_cents
    before_primary = balances.closing_cents(Account.primary)

    opening = described_class.new(name: "Itaú", amount: "300,00", source_account_id: Account.primary.id.to_s)
    expect(opening.save).to be true

    expect(opening.account.name).to eq("Itaú")
    expect(Budgeting::MonthSummary.new(month: may).current_balance_cents).to eq(before_total)
    expect(balances.closing_cents(opening.account)).to eq(30_000)
    expect(balances.closing_cents(Account.primary)).to eq(before_primary - 30_000)
    transfer = Transfer.last
    expect([ transfer.date, transfer.note ]).to eq([ Date.new(2026, 5, 20), "saldo de abertura" ])
  end

  it "opens an empty account when no amount is given" do
    opening = described_class.new(name: "Itaú", amount: "", source_account_id: Account.primary.id.to_s)
    expect(opening.save).to be true
    expect(Transfer.count).to eq(0)
    expect(balances.closing_cents(opening.account)).to eq(0)
  end

  it "refuses an amount that doesn't parse" do
    opening = described_class.new(name: "Itaú", amount: "abc", source_account_id: Account.primary.id.to_s)
    expect(opening.save).to be false
    expect(opening.errors[:amount]).to include("não é um valor válido")
    expect(Account.find_by(name: "Itaú")).to be_nil
  end

  it "refuses a blank name and creates nothing" do
    opening = described_class.new(name: "", amount: "300,00", source_account_id: Account.primary.id.to_s)
    expect(opening.save).to be false
    expect(opening.errors[:name]).to be_present
    expect(Transfer.count).to eq(0)
  end
end
