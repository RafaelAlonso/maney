require "rails_helper"

RSpec.describe Budgeting::MonthlySeries do
  let(:months) { (1..12).map { |m| Date.new(2026, m, 1) } }

  def series(active:, amounts: {})
    described_class.new(months:, active_months: active, amounts:)
  end

  it "reports zero for a month with no amount" do
    expect(series(active: months).cents(Date.new(2026, 5, 1))).to eq 0
  end

  it "renders an inactive month as a gap, never as a zero bar" do
    active = months.first(3)
    values = series(active:, amounts: { Date.new(2026, 1, 1) => 5_000 }).values_for_chart

    expect(values[0]).to eq 5_000
    # An active month with nothing spent is a real zero...
    expect(values[1]).to eq 0
    # ...while a month that has not happened is absent.
    expect(values[3]).to be_nil
  end

  it "averages over active months only, counting an active empty month as zero" do
    active = months.first(3)
    amounts = { Date.new(2026, 1, 1) => 900, Date.new(2026, 2, 1) => 300,
                Date.new(2026, 7, 1) => 99_999 }

    # (900 + 300 + 0) / 3 — July is inactive and must not pull the average up.
    expect(series(active:, amounts:).average_cents).to eq 400
  end

  it "returns a zero average when no month is active" do
    expect(series(active: []).average_cents).to eq 0
  end

  it "totals and reports presence over active months only" do
    active = months.first(2)
    amounts = { Date.new(2026, 1, 1) => 700, Date.new(2026, 9, 1) => 5_000 }

    expect(series(active:, amounts:).total_cents).to eq 700
    expect(series(active:, amounts:)).to be_any
    expect(series(active:, amounts: { Date.new(2026, 9, 1) => 5_000 })).not_to be_any
  end

  it "subtracts another series month by month, keeping the active mask" do
    active = months.first(2)
    income = series(active:, amounts: { Date.new(2026, 1, 1) => 10_000, Date.new(2026, 2, 1) => 4_000 })
    spending = series(active:, amounts: { Date.new(2026, 1, 1) => 3_000, Date.new(2026, 2, 1) => 9_000 })

    profit = income - spending

    expect(profit.cents(Date.new(2026, 1, 1))).to eq 7_000
    expect(profit.cents(Date.new(2026, 2, 1))).to eq(-5_000)
    expect(profit.values_for_chart[5]).to be_nil
  end
end
