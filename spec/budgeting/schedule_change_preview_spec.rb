require "rails_helper"

RSpec.describe Budgeting::ScheduleChangePreview do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:today) { Date.new(2026, 7, 28) }
  let(:card) { create_card!(closing_day: 5, due_day: 12) }

  def preview(closing_day:, due_day:)
    described_class.new(
      card:,
      proposed: Budgeting::Schedule.new(closing_day:, due_day:, valid_from: Date.new(2026, 7, 3)),
      today:
    )
  end

  # Closing and due days are independent, so moving the closing day past the due
  # day flips Statement#nominal_due's "due in the month after the cycle" rule.
  # The whole open chain then lands a month later — the one-time gap the user had
  # no way to see coming.
  it "shows the month-long postponement a closing-day change past the due day causes" do
    rows = preview(closing_day: 20, due_day: 12).rows

    expect(rows.map { |row| row.cycle.strftime("%m/%Y") }).to eq %w[08/2026 09/2026 10/2026]
    # 12/09 is a Saturday, so it lands on the 14th; the other two are weekdays.
    expect(rows.map(&:before_due)).to eq [Date.new(2026, 8, 12), Date.new(2026, 9, 14), Date.new(2026, 10, 12)]
    # Each cycle is now due the month after it closes: 08 → 12/09 (Sat) → 14/09.
    expect(rows.map(&:after_due)).to eq [Date.new(2026, 9, 14), Date.new(2026, 10, 12), Date.new(2026, 11, 12)]
    expect(rows).to all(be_shifts)
  end

  it "reports no shift when the due dates stay where they are" do
    expect(preview(closing_day: 3, due_day: 12).shifts?).to be false
  end

  it "reports a shift when only the due day moves" do
    change = preview(closing_day: 5, due_day: 13)

    expect(change.shifts?).to be true
    expect(change.rows.first.after_due).to eq Date.new(2026, 8, 13)
  end

  describe "#unbilled_installments" do
    # sofá 10x bought 10/03: the first installment falls in the statement closing
    # 03/04, and one per statement after that. By 28/07 the statements closing in
    # April, May, June and July have billed 1/10 … 4/10.
    it "counts only the installments no statement has billed yet" do
      InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                  card:, category: Category.find_by!(role: "others"),
                                  date: Date.new(2026, 3, 10))

      expect(preview(closing_day: 20, due_day: 12).unbilled_installments).to eq 6
    end

    it "ignores standalone credit expenses — only a plan is postponed as a plan" do
      Expense.create!(name: "mercado", amount_cents: 10_000, payment_method: "credit",
                      card:, category: Category.find_by!(role: "others"), date: Date.new(2026, 7, 25))

      expect(preview(closing_day: 20, due_day: 12).unbilled_installments).to eq 0
    end

    it "is zero on a card with nothing entered" do
      expect(preview(closing_day: 20, due_day: 12).unbilled_installments).to eq 0
    end
  end
end
