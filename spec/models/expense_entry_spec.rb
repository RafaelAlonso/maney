require "rails_helper"

RSpec.describe ExpenseEntry do
  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }
  let(:card) { create_card! }

  def entry(overrides = {})
    described_class.new({ name: "padaria", amount: "50,00", date: "2026-03-10",
                          category_id: others.id.to_s, payment_method: "debit" }.merge(overrides))
  end

  describe "#save (avulso)" do
    it "creates a debit expense (AC 4)" do
      e = entry
      expect(e.save).to be true
      expect(e.record).to be_a(Expense)
      expect(e.record.amount_cents).to eq 5_000
    end

    it "defaults to the reserved 'others' category when blank (AC 12)" do
      e = entry(category_id: "")
      expect(e.save).to be true
      expect(e.record.category).to eq others
    end

    it "creates a credit expense bound to the card (AC 5)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, name: "mercado", amount: "200,00", date: "2026-03-04")
      expect(e.save).to be true
      statement = Budgeting::StatementSet.statement_of(e.record)
      expect(statement.effective_due).to eq Date.new(2026, 3, 12)
    end

    it "rejects unparseable and non-positive amounts (AC 14)" do
      expect(entry(amount: "abc").save).to be false
      expect(entry(amount: "0,00").save).to be false
      expect(entry(amount: "-5").save).to be false
    end

    it "surfaces model errors (credit without card, date before first month) (AC 13/19)" do
      e = entry(payment_method: "credit", card_id: "")
      expect(e.save).to be false
      expect(e.errors[:card]).to be_present

      e = entry(date: "2026-02-10")
      expect(e.save).to be false
      expect(e.errors[:date]).to be_present
    end
  end

  describe "#save (parcelado)" do
    it "creates the whole series at once (AC 6)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1",
                name: "sofá", amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      expect(e.save).to be true
      expect(e.record).to be_a(InstallmentPurchase)
      expect(e.record.expenses.order(:installment_number).map(&:name).first).to eq "sofá 1/10"
      expect(e.record.expenses.count).to eq 10
      expect(e.record.expenses.sum(:amount_cents)).to eq 100_000
    end

    it "puts the cents remainder on the first created installment (AC 7)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1",
                amount: "100,00", installments_count: "3", date: "2026-03-10")
      e.save
      expect(e.record.expenses.order(:installment_number).map(&:amount_cents)).to eq [3_334, 3_333, 3_333]
    end

    it "starts at the given first installment (AC 8)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", first_installment: "4", date: "2026-03-10")
      e.save
      expect(e.record.expenses.order(:installment_number).map(&:installment_number)).to eq (4..10).to_a
    end
  end

  describe "#update" do
    it "updates a plain expense" do
      e = entry
      e.save
      updated = entry(name: "café", amount: "10,00")
      expect(updated.update(e.record)).to be true
      expect(e.record.reload.name).to eq "café"
    end

    it "recalculates the whole series on purchase edit (AC 9)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      purchase = e.record
      updated = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                      amount: "500,00", installments_count: "5", date: "2026-03-10")
      expect(updated.update(purchase)).to be true
      expect(purchase.reload.expenses.count).to eq 5
      expect(purchase.expenses.sum(:amount_cents)).to eq 50_000
    end

    it "keeps the series intact when the purchase edit is invalid" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      bad = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "",
                  amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      expect(bad.update(e.record.reload)).to be false
      expect(e.record.reload.expenses.count).to eq 10
    end
  end

  describe ".from" do
    it "prefills from a purchase" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      prefilled = described_class.from(e.record)
      expect(prefilled.amount).to eq "1.000,00"
      expect(prefilled.installment?).to be true
    end
  end
end
