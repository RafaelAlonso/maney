require "rails_helper"

RSpec.describe Expense do
  let(:card) { create_card }
  let(:mercado) { category("mercado") }

  def expense(**attrs)
    Expense.new({ name: "padaria", amount_cents: 5_000, date: Date.new(2026, 3, 10),
                  payment_method: "debit", category: mercado }.merge(attrs))
  end

  it "exige valor positivo e método conhecido" do
    expect(expense).to be_valid
    expect(expense(amount_cents: 0)).not_to be_valid
    expect(expense(amount_cents: -100)).not_to be_valid
    expect(expense(payment_method: "pix")).not_to be_valid
  end

  it "crédito exige cartão; débito e dinheiro não levam cartão" do
    expect(expense(payment_method: "credit")).not_to be_valid
    expect(expense(payment_method: "credit", card: card)).to be_valid
    expect(expense(payment_method: "debit", card: card)).not_to be_valid
    expect(expense(payment_method: "cash", card: nil)).to be_valid
  end

  it "a categoria cartão de crédito é aceita no débito (pagamento de fatura) e recusada no crédito" do
    expect(expense(payment_method: "debit", category: credit_card_category)).to be_valid
    expect(expense(payment_method: "credit", card: card, category: credit_card_category)).not_to be_valid
  end

  it "gasto comum exige data; data anterior ao primeiro mês é bloqueada" do
    expect(expense(date: nil)).not_to be_valid
    Setting.create!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    expect(expense(date: Date.new(2026, 2, 28))).not_to be_valid
    expect(expense(date: Date.new(2026, 3, 1))).to be_valid
  end
end
