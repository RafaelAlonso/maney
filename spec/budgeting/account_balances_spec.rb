require "rails_helper"

RSpec.describe Budgeting::AccountBalances do
  let(:march) { Date.new(2026, 3, 1) }
  let(:april) { Date.new(2026, 4, 1) }
  let(:mercado) { category("mercado") }

  before do
    create_setting!(first_month: march, initial_balance_cents: 100_000)
    create_reserved_categories!
  end

  def balances(month) = described_class.new(month:)

  def primary = Account.primary
  def wallet = Account.wallet

  # primary 1.000 + 500 income − 300 to Itaú − 50 saque; Itaú 300 − 100 débito;
  # carteira 50 saque − 20 dinheiro.
  def build_march
    itau = Account.create!(name: "Itaú")
    Income.create!(name: "salário", amount_cents: 50_000, date: Date.new(2026, 3, 2), account: primary)
    Transfer.create!(from_account: primary, to_account: itau, amount_cents: 30_000, date: Date.new(2026, 3, 5))
    Expense.create!(name: "feira", amount_cents: 10_000, date: Date.new(2026, 3, 6), payment_method: "debit",
                    category: mercado, account: itau)
    Transfer.create!(from_account: primary, to_account: wallet, amount_cents: 5_000, date: Date.new(2026, 3, 7),
                     note: "saque")
    Expense.create!(name: "pão", amount_cents: 2_000, date: Date.new(2026, 3, 8), payment_method: "cash",
                    category: mercado, account: wallet)
    itau
  end

  it "the primary account opens the first month with saldo inicial; every other account with 0" do
    itau = Account.create!(name: "Itaú")
    expect(balances(march).opening_cents(primary)).to eq(100_000)
    expect(balances(march).opening_cents(wallet)).to eq(0)
    expect(balances(march).opening_cents(itau)).to eq(0)
  end

  it "income in, débito and dinheiro out, transfers move between accounts" do
    itau = build_march
    month = balances(march)
    expect(month.closing_cents(primary)).to eq(115_000)
    expect(month.closing_cents(itau)).to eq(20_000)
    expect(month.closing_cents(wallet)).to eq(3_000)
  end

  it "carries each account's balance into the next month" do
    itau = build_march
    Income.create!(name: "freela", amount_cents: 10_000, date: Date.new(2026, 4, 2), account: itau)

    [ primary, itau, wallet ].each do |account|
      expect(balances(april).opening_cents(account)).to eq(balances(march).closing_cents(account))
    end
    expect(balances(april).closing_cents(itau)).to eq(30_000)
  end

  it "crédito purchases never move an account; a bill payment does, on its own date" do
    card = create_card!
    Expense.create!(name: "tv", amount_cents: 20_000, date: Date.new(2026, 3, 3), payment_method: "credit",
                    card:, category: mercado)
    expect(balances(march).closing_cents(primary)).to eq(100_000)

    Expense.create!(name: "fatura", amount_cents: 20_000, date: Date.new(2026, 4, 12), payment_method: "debit",
                    category: credit_card_category, account: primary)
    expect(balances(march).closing_cents(primary)).to eq(100_000)
    expect(balances(april).closing_cents(primary)).to eq(80_000)
  end

  it "the accounts always add up to saldo atual" do
    itau = build_march
    card = create_card!
    Expense.create!(name: "tv", amount_cents: 20_000, date: Date.new(2026, 3, 3), payment_method: "credit",
                    card:, category: mercado)
    Expense.create!(name: "fatura", amount_cents: 20_000, date: Date.new(2026, 4, 12), payment_method: "debit",
                    category: credit_card_category, account: itau)
    Transfer.create!(from_account: itau, to_account: primary, amount_cents: 1_000, date: Date.new(2026, 5, 1))

    [ march, april, Date.new(2026, 5, 1), Date.new(2026, 6, 1) ].each do |month|
      expect(balances(month).total_closing_cents)
        .to eq(Budgeting::MonthSummary.new(month:).current_balance_cents), "mismatch in #{month}"
    end
  end

  it "movements carry a running balance that ends at closing_cents" do
    itau = build_march
    [ primary, itau, wallet ].each do |account|
      month = balances(march)
      movements = month.movements(account)
      expect(movements.last.balance_after_cents).to eq(month.closing_cents(account))
      expect(movements.first.balance_after_cents).to eq(month.opening_cents(account) + movements.first.amount_cents)
    end

    names = balances(march).movements(primary).map { |movement| [ movement.name, movement.amount_cents ] }
    expect(names).to eq([ [ "salário", 50_000 ], [ "transferência para Itaú", -30_000 ], [ "saque", -5_000 ] ])
    expect(balances(march).movements(itau).first.name).to eq("transferência de Conta principal")
  end

  it "an archived account still counts" do
    itau = build_march
    itau.archive!
    expect(balances(march).closing_cents(itau)).to eq(20_000)
    expect(balances(march).total_closing_cents).to eq(138_000)
  end
end
