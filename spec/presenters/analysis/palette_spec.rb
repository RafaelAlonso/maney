require "rails_helper"

RSpec.describe Analysis::Palette do
  let(:mercado) { Category.create!(name: "mercado") }

  # Relative luminance is enough to assert "gets lighter"; the exact steps are
  # an implementation detail, the monotonic direction is the contract.
  def brightness(hex)
    hex.delete_prefix("#").scan(/../).sum { |pair| pair.to_i(16) }
  end

  it "starts the ramp on the category's own colour" do
    expect(described_class.new.shades_for(mercado, count: 4).first)
      .to eq described_class.new.color_for(mercado)
  end

  it "returns one shade per slice" do
    expect(described_class.new.shades_for(mercado, count: 7).size).to eq 7
  end

  it "gets lighter with every step, so shade encodes rank" do
    shades = described_class.new.shades_for(mercado, count: 5)

    expect(shades.map { |hex| brightness(hex) }).to eq shades.map { |hex| brightness(hex) }.sort
    expect(brightness(shades.last)).to be > brightness(shades.first)
  end

  it "keeps the lightest shade off the white card" do
    # The mix is capped at 60% white, so even the last slice keeps enough of the
    # hue to be seen against #ffffff.
    expect(brightness(described_class.new.shades_for(mercado, count: 20).last)).to be < brightness("#ffffff")
  end

  it "returns the base colour alone for a single slice" do
    palette = described_class.new
    expect(palette.shades_for(mercado, count: 1)).to eq [ palette.color_for(mercado) ]
  end

  it "returns nothing for no slices" do
    expect(described_class.new.shades_for(mercado, count: 0)).to eq []
  end

  it "is deterministic" do
    expect(described_class.new.shades_for(mercado, count: 6))
      .to eq described_class.new.shades_for(mercado, count: 6)
  end

  it "emits valid six-digit hex" do
    expect(described_class.new.shades_for(mercado, count: 9)).to all(match(/\A#\h{6}\z/))
  end

  describe "shared chart palette tokens" do
    it "emits CSS-var tokens for the chart roles resolved client-side per theme" do
      expect(Analysis::Palette::PRIMARY).to eq "var(--chart-1)"
      expect(Analysis::Palette::OUTFLOW).to eq "var(--chart-2)"
      expect(Analysis::Palette::AVERAGE).to eq "var(--chart-average)"
      expect(Analysis::Palette::POSITIVE).to eq "var(--chart-positive)"
      expect(Analysis::Palette::NEGATIVE).to eq "var(--chart-negative)"
      expect(Analysis::Palette::GRID).to eq "var(--chart-grid)"
      expect(Analysis::Palette::AXIS).to eq "var(--chart-axis)"
      expect(Analysis::Palette::MUTED_INK).to eq "var(--chart-label)"
    end

    it "maps a category to the chart var of its ordered slot" do
      expect(described_class.new.chart_var_for(mercado)).to eq "var(--chart-1)"
    end

    it "keeps color_for on hex, so the drill-down ramp is untouched" do
      expect(described_class.new.color_for(mercado)).to match(/\A#\h{6}\z/)
    end
  end
end
