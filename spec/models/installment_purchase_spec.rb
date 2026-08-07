require "rails_helper"

RSpec.describe InstallmentPurchase do
  let(:card) { create_card }
  let(:sofa_attrs) do
    { name: "sofá", total_cents: 100_000, installments_count: 10,
      date: Date.new(2026, 3, 10), card: card, category: category("casa") }
  end

  it "AC 9 (creation): generates the 10 expenses sofá 1/10..10/10 of R$ 100 at once" do
    purchase = InstallmentPurchase.create!(**sofa_attrs)
    expenses = purchase.expenses.order(:installment_number)
    expect(expenses.map(&:name)).to eq((1..10).map { |k| "sofá #{k}/10" })
    expect(expenses.map(&:amount_cents)).to all(eq(10_000))
    expect(expenses.map(&:payment_method).uniq).to eq([ "credit" ])
    expect(expenses.map(&:date).uniq).to eq([ nil ])
  end

  it "AC 11 (creation): first installment 4 generates only sofá 4/10..10/10" do
    purchase = InstallmentPurchase.create!(**sofa_attrs, first_installment: 4)
    expect(purchase.expenses.order(:installment_number).map(&:name))
      .to eq((4..10).map { |k| "sofá #{k}/10" })
  end

  it "validates: minimum 2 installments, first installment in 1..N, positive total" do
    expect(InstallmentPurchase.new(**sofa_attrs, installments_count: 1)).not_to be_valid
    expect(InstallmentPurchase.new(**sofa_attrs, first_installment: 11)).not_to be_valid
    expect(InstallmentPurchase.new(**sofa_attrs, first_installment: 0)).not_to be_valid
    expect(InstallmentPurchase.new(**sofa_attrs, total_cents: 0)).not_to be_valid
  end

  it "Decision 1: accepts 120 installments (ten years) and refuses 121, without duplicating the minimum message" do
    at_max = InstallmentPurchase.new(**sofa_attrs, total_cents: 1_200_00, installments_count: 120)
    expect(at_max).to be_valid

    over_max = InstallmentPurchase.new(**sofa_attrs, total_cents: 1_200_00, installments_count: 121)
    expect(over_max).not_to be_valid
    expect(over_max.errors[:installments_count]).to eq([ "deve ter entre 2 e 120 parcelas" ])
  end

  it "Decision 1: keeps the minimum of 2 installments using the same message as the upper limit" do
    under_min = InstallmentPurchase.new(**sofa_attrs, installments_count: 1)
    expect(under_min).not_to be_valid
    expect(under_min.errors[:installments_count]).to eq([ "deve ter entre 2 e 120 parcelas" ])
  end

  it "refuses the reserved credit-card category (it's a credit purchase)" do
    expect(InstallmentPurchase.new(**sofa_attrs, category: credit_card_category)).not_to be_valid
  end

  it "Fix 4: refuses a total smaller than the installment count (an installment would get 0 cents)" do
    purchase = InstallmentPurchase.new(**sofa_attrs, total_cents: 9, installments_count: 10)
    expect(purchase).not_to be_valid
    expect(purchase.errors[:total_cents]).to be_present
  end

  it "Fix 4: a total equal to the installment count is the valid limit — generates installments of exactly 1 cent" do
    purchase = InstallmentPurchase.create!(**sofa_attrs, total_cents: 10, installments_count: 10)
    expect(purchase.expenses.pluck(:amount_cents).uniq).to eq([ 1 ])
  end

  # regenerate_installments! declares that the transaction lives in it precisely
  # so it doesn't depend on the caller. Today the only caller (ExpenseEntry) wraps
  # everything in its own transaction, so that guarantee is never exercised — this
  # example calls the method directly, with no external transaction, and proves
  # that a failure mid-recreate doesn't leave the series half-built.
  it "recovers the whole series when regeneration fails, with no external transaction" do
    credit_card_category
    purchase = InstallmentPurchase.create!(**sofa_attrs)
    original = purchase.expenses.order(:installment_number).pluck(:name, :amount_cents)
    expect(original.size).to eq 10

    # Every generated installment becomes invalid (Expense refuses the reserved
    # card category on a credit expense), without going through the purchase's
    # validations — which would block the swap.
    purchase.update_column(:category_id, Category.find_by!(role: "credit_card").id)
    purchase.reload

    expect { purchase.regenerate_installments! }.to raise_error(ActiveRecord::RecordInvalid)
    expect(purchase.expenses.reload.order(:installment_number).pluck(:name, :amount_cents)).to eq original
  end
end
