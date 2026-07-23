require "rails_helper"

RSpec.describe Budgeting::InstallmentSplit do
  it "AC 10: R$ 100 in 3x becomes 33,34 + 33,33 + 33,33 — leftover on the first, sum equals the total" do
    parts = described_class.call(total_cents: 10_000, count: 3)
    expect(parts.map(&:amount_cents)).to eq([3_334, 3_333, 3_333])
    expect(parts.map(&:number)).to eq([1, 2, 3])
    expect(parts.sum(&:amount_cents)).to eq(10_000)
  end

  it "AC 11: first installment 4 of 10 creates only 4..10, dividing by the total installment count" do
    parts = described_class.call(total_cents: 100_000, count: 10, first: 4)
    expect(parts.map(&:number)).to eq([4, 5, 6, 7, 8, 9, 10])
    expect(parts.map(&:amount_cents)).to all(eq(10_000))
  end

  it "with a first installment and inexact division, the leftover goes to the first installment created" do
    parts = described_class.call(total_cents: 10_000, count: 3, first: 2)
    expect(parts.map(&:amount_cents)).to eq([3_334, 3_333])
    expect(parts.first.number).to eq(2)
  end

  it "a first installment equal to N creates a single installment N/N" do
    parts = described_class.call(total_cents: 10_000, count: 3, first: 3)
    expect(parts.map(&:number)).to eq([3])
  end
end
