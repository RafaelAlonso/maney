require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#brl" do
    it { expect(helper.brl(nil)).to eq "—" }
    it { expect(helper.brl(0)).to eq "R$ 0,00" }
    it { expect(helper.brl(123_456_789)).to eq "R$ 1.234.567,89" }
    it { expect(helper.brl(-1_234)).to eq "-R$ 12,34" }
    it { expect(helper.brl(-123_456_789)).to eq "-R$ 1.234.567,89" }
  end

  describe "#statement_due_label" do
    let(:card) { create_card }

    it "omits the year when the due date falls in the current one" do
      statement = Budgeting::StatementAttribution.statement_for(card:, date: Date.new(2026, 3, 6))

      expect(helper.statement_due_label(statement, today: Date.new(2026, 3, 20))).to eq "vence 13/04"
    end

    it "shows the year across the rollover, so January/2027 can't be read as this year" do
      statement = Budgeting::StatementAttribution.statement_for(card:, date: Date.new(2026, 12, 10))

      expect(helper.statement_due_label(statement, today: Date.new(2026, 12, 20))).to eq "vence 12/01/2027"
    end
  end

  describe "#statement_period_label" do
    def row(period_start, period_end)
      Budgeting::CardStatements::Row.new(statement: nil, expenses: [], total_cents: 0,
                                         period_start:, period_end:)
    end

    it "omits the year when the whole period falls in the current one" do
      label = helper.statement_period_label(row(Date.new(2026, 3, 5), Date.new(2026, 4, 2)),
                                            today: Date.new(2026, 3, 20))

      expect(label).to eq "05/03 – 02/04"
    end

    it "shows the year when the period crosses into another one" do
      label = helper.statement_period_label(row(Date.new(2026, 12, 4), Date.new(2027, 1, 4)),
                                            today: Date.new(2026, 12, 20))

      expect(label).to eq "04/12/2026 – 04/01/2027"
    end
  end
end
