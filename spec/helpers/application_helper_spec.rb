require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#brl" do
    it { expect(helper.brl(nil)).to eq "—" }
    it { expect(helper.brl(0)).to eq "R$ 0,00" }
    it { expect(helper.brl(123_456_789)).to eq "R$ 1.234.567,89" }
    it { expect(helper.brl(-1_234)).to eq "R$ -12,34" }
  end
end
