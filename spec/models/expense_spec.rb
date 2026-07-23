require "rails_helper"

RSpec.describe Expense do
  let(:card) { create_card }
  let(:mercado) { category("mercado") }

  def expense(**attrs)
    Expense.new({ name: "padaria", amount_cents: 5_000, date: Date.new(2026, 3, 10),
                  payment_method: "debit", category: mercado }.merge(attrs))
  end

  it "requires a positive amount and a known method" do
    expect(expense).to be_valid
    expect(expense(amount_cents: 0)).not_to be_valid
    expect(expense(amount_cents: -100)).not_to be_valid
    expect(expense(payment_method: "pix")).not_to be_valid
  end

  it "credit requires a card; debit and cash carry no card" do
    expect(expense(payment_method: "credit")).not_to be_valid
    expect(expense(payment_method: "credit", card: card)).to be_valid
    expect(expense(payment_method: "debit", card: card)).not_to be_valid
    expect(expense(payment_method: "cash", card: nil)).to be_valid
  end

  it "the credit-card category is accepted on debit (statement payment) and rejected on credit" do
    expect(expense(payment_method: "debit", category: credit_card_category)).to be_valid
    expect(expense(payment_method: "credit", card: card, category: credit_card_category)).not_to be_valid
  end

  it "a standalone expense requires a date; a date before the first month is blocked" do
    expect(expense(date: nil)).not_to be_valid
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    expect(expense(date: Date.new(2026, 2, 28))).not_to be_valid
    expect(expense(date: Date.new(2026, 3, 1))).to be_valid
  end

  it "an installment requires a number, has no date of its own and is always on credit" do
    purchase = InstallmentPurchase.create!(
      name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card: card, category: mercado
    )
    part = purchase.expenses.first

    without_number = part.dup.tap { |e| e.installment_number = nil }
    expect(without_number).not_to be_valid
    expect(without_number.errors[:installment_number]).to include("é obrigatório numa parcela")

    with_own_date = part.dup.tap { |e| e.date = Date.new(2026, 3, 10) }
    expect(with_own_date).not_to be_valid
    expect(with_own_date.errors[:date]).to include("parcela não tem data própria")

    not_credit = part.dup.tap { |e| e.payment_method = "debit" }
    expect(not_credit).not_to be_valid
    expect(not_credit.errors[:payment_method]).to include("parcela é sempre no crédito")
  end

  it "an installment number only applies to installments" do
    non_installment = expense(installment_number: 2)
    expect(non_installment).not_to be_valid
    expect(non_installment.errors[:installment_number]).to include("só se aplica a parcelas")
  end
end
