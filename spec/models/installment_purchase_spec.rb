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

  it "Decision 1: aceita 120 parcelas (dez anos) e recusa 121, sem duplicar a mensagem do mínimo" do
    at_max = InstallmentPurchase.new(**sofa_attrs, total_cents: 1_200_00, installments_count: 120)
    expect(at_max).to be_valid

    over_max = InstallmentPurchase.new(**sofa_attrs, total_cents: 1_200_00, installments_count: 121)
    expect(over_max).not_to be_valid
    expect(over_max.errors[:installments_count]).to eq(["deve ter entre 2 e 120 parcelas"])
  end

  it "Decision 1: mantém o mínimo de 2 parcelas usando a mesma mensagem do limite superior" do
    under_min = InstallmentPurchase.new(**sofa_attrs, installments_count: 1)
    expect(under_min).not_to be_valid
    expect(under_min.errors[:installments_count]).to eq(["deve ter entre 2 e 120 parcelas"])
  end

  it "recusa a categoria reservada cartão de crédito (é compra no crédito)" do
    expect(InstallmentPurchase.new(**sofa_attrs, category: credit_card_category)).not_to be_valid
  end

  it "Fix 4: recusa total menor que o número de parcelas (parcela ficaria com 0 centavos)" do
    purchase = InstallmentPurchase.new(**sofa_attrs, total_cents: 9, installments_count: 10)
    expect(purchase).not_to be_valid
    expect(purchase.errors[:total_cents]).to be_present
  end

  it "Fix 4: total igual ao número de parcelas é o limite válido — gera parcelas de exatamente 1 centavo" do
    purchase = InstallmentPurchase.create!(**sofa_attrs, total_cents: 10, installments_count: 10)
    expect(purchase.expenses.pluck(:amount_cents).uniq).to eq([1])
  end

  # regenerate_installments! declara que a transação vive nele justamente para
  # não depender de quem chama. Hoje o único chamador (ExpenseEntry) embrulha
  # tudo numa transação própria, então essa garantia nunca é exercida — este
  # exemplo chama o método direto, sem transação externa, e prova que uma falha
  # no meio do recria não deixa a série pela metade.
  it "recupera a série inteira quando a regeneração falha, sem transação externa" do
    credit_card_category
    purchase = InstallmentPurchase.create!(**sofa_attrs)
    original = purchase.expenses.order(:installment_number).pluck(:name, :amount_cents)
    expect(original.size).to eq 10

    # Toda parcela gerada passa a ser inválida (Expense recusa a categoria
    # reservada de cartão num gasto no crédito), sem passar pelas validações
    # do purchase — que barrariam a troca.
    purchase.update_column(:category_id, Category.find_by!(role: "credit_card").id)
    purchase.reload

    expect { purchase.regenerate_installments! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(purchase.expenses.reload.order(:installment_number).pluck(:name, :amount_cents)).to eq original
  end
end
