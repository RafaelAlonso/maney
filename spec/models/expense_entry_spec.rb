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

    it "falls back to the reserved 'others' category when category_id no longer resolves (Fix 5)" do
      stale = category("temporária")
      stale_id = stale.id
      stale.destroy!

      e = entry(category_id: stale_id.to_s)
      expect(e.save).to be true
      expect(e.record.category).to eq others
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

    it "maps the total_cents validation error onto :amount, the form's own field (Fix 4)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "0,03", installments_count: "10", date: "2026-03-10")
      expect(e.save).to be false
      expect(e.errors[:amount]).to be_present
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

    it "keeps the series' actual content intact when the purchase edit is invalid" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      purchase = e.record
      original_names = purchase.expenses.order(:installment_number).pluck(:name)
      original_amounts = purchase.expenses.order(:installment_number).pluck(:amount_cents)
      original_sum = purchase.expenses.sum(:amount_cents)

      bad = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "",
                  amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      expect(bad.update(purchase.reload)).to be false

      purchase.reload
      expect(purchase.expenses.order(:installment_number).pluck(:name)).to eq original_names
      expect(purchase.expenses.order(:installment_number).pluck(:amount_cents)).to eq original_amounts
      expect(purchase.expenses.sum(:amount_cents)).to eq original_sum
    end

    it "keeps the series' actual content intact when regenerate_installments! itself fails after the purchase save succeeded (Fix 1/Fix 3)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      purchase = e.record
      original_names = purchase.expenses.order(:installment_number).pluck(:name)
      original_amounts = purchase.expenses.order(:installment_number).pluck(:amount_cents)
      original_sum = purchase.expenses.sum(:amount_cents)

      # Força regenerate_installments! a falhar depois que o purchase.save já
      # foi aceito — o cenário que expõe se update_purchase deixa a exceção
      # escapar ao invés de devolver false com o form re-renderizável.
      allow(purchase).to receive(:regenerate_installments!) do
        purchase.errors.add(:base, "falha forçada para teste")
        raise ActiveRecord::RecordInvalid, purchase
      end

      updated = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                      amount: "500,00", installments_count: "5", date: "2026-03-10")
      result = nil
      expect { result = updated.update(purchase) }.not_to raise_error
      expect(result).to be false

      purchase.reload
      expect(purchase.expenses.order(:installment_number).pluck(:name)).to eq original_names
      expect(purchase.expenses.order(:installment_number).pluck(:amount_cents)).to eq original_amounts
      expect(purchase.expenses.sum(:amount_cents)).to eq original_sum
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
