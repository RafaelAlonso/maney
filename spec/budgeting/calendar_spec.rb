require "rails_helper"

RSpec.describe Budgeting::Calendar do
  it "AC 7: dia 30 em fevereiro/2026 transborda para 02/03/2026" do
    expect(described_class.nominal_date(2026, 2, 30)).to eq(Date.new(2026, 3, 2))
  end

  it "edge: fevereiro bissexto — dia 30 em fevereiro/2028 transborda para 01/03/2028" do
    expect(described_class.nominal_date(2028, 2, 30)).to eq(Date.new(2028, 3, 1))
  end

  it "dia existente não transborda" do
    expect(described_class.nominal_date(2026, 3, 5)).to eq(Date.new(2026, 3, 5))
    expect(described_class.nominal_date(2026, 1, 31)).to eq(Date.new(2026, 1, 31))
  end

  it "AC 5: fechamento nominal 05/04/2026 (domingo) recua para sexta 03/04" do
    expect(described_class.effective_closing(Date.new(2026, 4, 5))).to eq(Date.new(2026, 4, 3))
  end

  it "AC 6: vencimento nominal 12/04/2026 (domingo) avança para segunda 13/04" do
    expect(described_class.effective_due(Date.new(2026, 4, 12))).to eq(Date.new(2026, 4, 13))
  end

  it "dia útil permanece igual nas duas direções" do
    friday = Date.new(2026, 3, 20)
    expect(described_class.effective_closing(friday)).to eq(friday)
    expect(described_class.effective_due(friday)).to eq(friday)
  end

  it "edge: transbordo caindo em fim de semana aplica transbordo primeiro, depois dia útil" do
    # dia 31 em abril/2027 transborda para 01/05/2027 (sábado):
    # fechamento recua para sexta 30/04; vencimento avança para segunda 03/05.
    nominal = described_class.nominal_date(2027, 4, 31)
    expect(nominal).to eq(Date.new(2027, 5, 1))
    expect(described_class.effective_closing(nominal)).to eq(Date.new(2027, 4, 30))
    expect(described_class.effective_due(nominal)).to eq(Date.new(2027, 5, 3))
  end
end
