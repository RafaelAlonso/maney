require "rails_helper"

RSpec.describe Budgeting::Solvency do
  before { create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 500_000) }
  before { create_reserved_categories! }

  let(:azul) { create_card! }
  let(:mercado) { category("mercado") }
  let(:august) { Date.new(2026, 8, 1) }

  def solvency(today: Date.new(2026, 8, 10))
    described_class.new(today:)
  end

  # Card Azul closes on day 5 and is due on day 12, so a purchase dated day 4 of
  # a month falls on the statement due in that same month, and one dated day 6
  # falls on the next month's.
  def credit(cents, on:, card: azul)
    Expense.create!(name: "compra", amount_cents: cents, payment_method: "credit",
                    category: mercado, card:, date: on)
  end

  # A statement payment as the app records one: an ordinary debit expense in the
  # reserved category, with no link to the statement it settles.
  def pay(cents, on:)
    Expense.create!(name: "pagamento fatura", amount_cents: cents, payment_method: "debit",
                    category: credit_card_category, date: on)
  end

  describe "the horizon" do
    it "lists every month from the current one to the last with committed debt (AC 1)" do
      InstallmentPurchase.create!(name: "sofá", total_cents: 240_000, installments_count: 24,
                                  date: Date.new(2026, 8, 4), card: azul, category: mercado)

      rows = solvency.rows
      expect(rows.size).to eq 24
      expect(rows.first.month).to eq august
      expect(rows.last.month).to eq Date.new(2028, 7, 1)
    end

    it "keeps a month with nothing due inside the horizon, as a zero row" do
      credit(100_000, on: Date.new(2026, 8, 4))
      credit(50_000, on: Date.new(2026, 10, 4))

      expect(solvency.rows.map { |row| [ row.month.month, row.committed_cents ] })
        .to eq [ [ 8, 100_000 ], [ 9, 0 ], [ 10, 50_000 ] ]
    end

    it "reports no committed debt at all as an empty horizon (AC 8)" do
      expect(solvency.rows).to be_empty
      expect(solvency).not_to be_any
    end
  end

  describe "what counts as committed" do
    it "counts a closed statement not yet paid in the month it is due (AC 6)" do
      credit(100_000, on: Date.new(2026, 8, 4)) # closed on 2026-08-05, due 2026-08-12
      expect(solvency.rows.first).to have_attributes(month: august, committed_cents: 100_000)
    end

    it "counts a statement still accumulating in the month it will come due (AC 7)" do
      credit(100_000, on: Date.new(2026, 8, 6)) # still open on 2026-08-10, due 2026-09-14
      expect(solvency.rows.map { |row| [ row.month, row.committed_cents ] })
        .to eq [ [ august, 0 ], [ Date.new(2026, 9, 1), 100_000 ] ]
    end

    it "counts each card's statement in the month that card is due (several cards)" do
      # Roxo's due day precedes its closing day, so its statement is due in the
      # month after the cycle's — the same purchase date lands a month later.
      roxo = create_card!(name: "Roxo", closing_day: 25, due_day: 5)
      credit(100_000, on: Date.new(2026, 8, 4))
      credit(50_000, on: Date.new(2026, 8, 4), card: roxo)

      expect(solvency.rows.map { |row| [ row.month.month, row.committed_cents ] })
        .to eq [ [ 8, 100_000 ], [ 9, 50_000 ] ]
    end

    it "accumulates the committed amounts month over month (AC 2)" do
      credit(100_000, on: Date.new(2026, 8, 4))
      # 2026-09-05 (the nominal closing) is a Saturday, so the effective closing
      # moves back to 2026-09-04 (Calendar#effective_closing) — a day-4 purchase
      # would then land exactly on it and, per attribution's ">" boundary, roll
      # into October's statement instead of September's. Day 3 keeps this on the
      # ordinary "same month" case the reference arithmetic describes.
      credit(50_000, on: Date.new(2026, 9, 3))

      expect(solvency.rows.map(&:cumulative_cents)).to eq [ 100_000, 150_000 ]
    end
  end

  describe "payments" do
    it "drops a statement that has been paid (AC 9)" do
      credit(100_000, on: Date.new(2026, 8, 4))
      pay(100_000, on: Date.new(2026, 8, 6))

      expect(solvency.rows).to be_empty
    end

    it "leaves the remainder of a partial payment committed" do
      credit(100_000, on: Date.new(2026, 8, 4))
      pay(30_000, on: Date.new(2026, 8, 6))

      expect(solvency.rows.first.committed_cents).to eq 70_000
    end
  end

  describe "debt from before the current month" do
    it "folds an unpaid past statement into the current month" do
      credit(100_000, on: Date.new(2026, 7, 4)) # falls due before September, never paid

      result = solvency(today: Date.new(2026, 9, 10))
      expect(result.arrears_cents).to eq 100_000
      expect(result.rows.map { |row| [ row.month, row.committed_cents ] })
        .to eq [ [ Date.new(2026, 9, 1), 100_000 ] ]
    end

    it "leaves no arrear when a past statement was paid late, in a later month" do
      # July's statement, settled in August. Flooring each past month on its own
      # would leave July's debt behind forever, because August's payment has
      # nothing of its own to cancel.
      credit(100_000, on: Date.new(2026, 7, 4))
      pay(100_000, on: Date.new(2026, 8, 20))

      result = solvency(today: Date.new(2026, 10, 10))
      expect(result.arrears_cents).to eq 0
      expect(result.rows).to be_empty
    end
  end
end
