require "rails_helper"

RSpec.describe Budgeting::InstallmentSplit do
  it "AC 10: R$ 100 em 3x vira 33,34 + 33,33 + 33,33 — sobra na primeira, soma igual ao total" do
    parts = described_class.call(total_cents: 10_000, count: 3)
    expect(parts.map(&:amount_cents)).to eq([3_334, 3_333, 3_333])
    expect(parts.map(&:number)).to eq([1, 2, 3])
    expect(parts.sum(&:amount_cents)).to eq(10_000)
  end

  it "AC 11: parcela inicial 4 de 10 cria só 4..10, dividindo pelo total de parcelas" do
    parts = described_class.call(total_cents: 100_000, count: 10, first: 4)
    expect(parts.map(&:number)).to eq([4, 5, 6, 7, 8, 9, 10])
    expect(parts.map(&:amount_cents)).to all(eq(10_000))
  end

  it "com parcela inicial e divisão inexata, a sobra vai para a primeira parcela criada" do
    parts = described_class.call(total_cents: 10_000, count: 3, first: 2)
    expect(parts.map(&:amount_cents)).to eq([3_334, 3_333])
    expect(parts.first.number).to eq(2)
  end

  it "parcela inicial igual a N cria uma única parcela N/N" do
    parts = described_class.call(total_cents: 10_000, count: 3, first: 3)
    expect(parts.map(&:number)).to eq([3])
  end
end
