require "rails_helper"

RSpec.describe InstallmentPurchase do
  let(:card) { create_card }
  let(:sofa_attrs) do
    { name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card: card, category: category("casa") }
  end

  it "AC 9 (criação): gera os 10 gastos sofá 1/10..10/10 de R$ 100 de uma vez" do
    purchase = InstallmentPurchase.create!(**sofa_attrs)
    expenses = purchase.expenses.order(:installment_number)
    expect(expenses.map(&:name)).to eq((1..10).map { |k| "sofá #{k}/10" })
    expect(expenses.map(&:amount_cents)).to all(eq(10_000))
    expect(expenses.map(&:payment_method).uniq).to eq(["credit"])
    expect(expenses.map(&:date).uniq).to eq([nil])
  end

  it "AC 11 (criação): parcela inicial 4 gera apenas sofá 4/10..10/10" do
    purchase = InstallmentPurchase.create!(**sofa_attrs, first_installment: 4)
    expect(purchase.expenses.order(:installment_number).map(&:name))
      .to eq((4..10).map { |k| "sofá #{k}/10" })
  end

  it "valida: mínimo 2 parcelas, parcela inicial em 1..N, total positivo" do
    expect(InstallmentPurchase.new(**sofa_attrs, installments_count: 1)).not_to be_valid
    expect(InstallmentPurchase.new(**sofa_attrs, first_installment: 11)).not_to be_valid
    expect(InstallmentPurchase.new(**sofa_attrs, first_installment: 0)).not_to be_valid
    expect(InstallmentPurchase.new(**sofa_attrs, total_cents: 0)).not_to be_valid
  end

  it "recusa a categoria reservada cartão de crédito (é compra no crédito)" do
    expect(InstallmentPurchase.new(**sofa_attrs, category: credit_card_category)).not_to be_valid
  end
end
