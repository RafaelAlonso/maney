require "rails_helper"

RSpec.describe BudgetBar do
  def bar(spent, budgeted, threshold = 80)
    described_class.new(spent_cents: spent, budgeted_cents: budgeted, threshold_percent: threshold)
  end

  describe "#state" do
    it "is neutral when nothing is budgeted (budget 0 is not an overrun)" do
      expect(bar(5000, 0).state).to eq(:neutral)
    end

    it "is on_track below the threshold" do
      expect(bar(7000, 10_000, 80).state).to eq(:on_track) # 70% < 80%
    end

    it "is near at or above the threshold but not over" do
      expect(bar(8000, 10_000, 80).state).to eq(:near) # exactly 80%
      expect(bar(10_000, 10_000, 80).state).to eq(:near) # spent == budget is not over
    end

    it "is over strictly above budget" do
      expect(bar(10_001, 10_000, 80).state).to eq(:over)
    end
  end

  describe "#fill_percent" do
    it "is proportional below budget" do
      expect(bar(2500, 10_000).fill_percent).to eq(25)
    end

    it "caps at 100 when over (the text carries the true overrun)" do
      expect(bar(15_000, 10_000).fill_percent).to eq(100)
    end

    it "is 0 when nothing is budgeted" do
      expect(bar(5000, 0).fill_percent).to eq(0)
    end
  end
end
