require "rails_helper"

RSpec.describe BrlMoney do
  describe ".parse" do
    it { expect(BrlMoney.parse("1.234,56")).to eq 123_456 }
    it { expect(BrlMoney.parse("900")).to eq 90_000 }
    it { expect(BrlMoney.parse("R$ 50,5")).to eq 5_050 }
    it { expect(BrlMoney.parse("-12,34")).to eq(-1_234) }
    it { expect(BrlMoney.parse("abc")).to be_nil }
    it { expect(BrlMoney.parse("")).to be_nil }
    it { expect(BrlMoney.parse(nil)).to be_nil }
  end

  describe ".format" do
    it { expect(BrlMoney.format(123_456)).to eq "1.234,56" }
    it { expect(BrlMoney.format(0)).to eq "0,00" }
    it { expect(BrlMoney.format(-1_234)).to eq "-12,34" }
    it { expect(BrlMoney.format(100_000_000)).to eq "1.000.000,00" }
  end
end
