require "rails_helper"

RSpec.describe Budgeting::Calendar do
  it "AC 7: day 30 in February/2026 overflows to 02/03/2026" do
    expect(described_class.nominal_date(2026, 2, 30)).to eq(Date.new(2026, 3, 2))
  end

  it "edge: leap February — day 30 in February/2028 overflows to 01/03/2028" do
    expect(described_class.nominal_date(2028, 2, 30)).to eq(Date.new(2028, 3, 1))
  end

  it "an existing day doesn't overflow" do
    expect(described_class.nominal_date(2026, 3, 5)).to eq(Date.new(2026, 3, 5))
    expect(described_class.nominal_date(2026, 1, 31)).to eq(Date.new(2026, 1, 31))
  end

  it "AC 5: nominal closing 05/04/2026 (Sunday) moves back to Friday 03/04" do
    expect(described_class.effective_closing(Date.new(2026, 4, 5))).to eq(Date.new(2026, 4, 3))
  end

  it "AC 6: nominal due date 12/04/2026 (Sunday) moves forward to Monday 13/04" do
    expect(described_class.effective_due(Date.new(2026, 4, 12))).to eq(Date.new(2026, 4, 13))
  end

  it "a business day stays the same in both directions" do
    friday = Date.new(2026, 3, 20)
    expect(described_class.effective_closing(friday)).to eq(friday)
    expect(described_class.effective_due(friday)).to eq(friday)
  end

  it "edge: an overflow landing on a weekend applies the overflow first, then the business day" do
    # day 31 in April/2027 overflows to 01/05/2027 (Saturday):
    # closing moves back to Friday 30/04; due date moves forward to Monday 03/05.
    nominal = described_class.nominal_date(2027, 4, 31)
    expect(nominal).to eq(Date.new(2027, 5, 1))
    expect(described_class.effective_closing(nominal)).to eq(Date.new(2027, 4, 30))
    expect(described_class.effective_due(nominal)).to eq(Date.new(2027, 5, 3))
  end
end
