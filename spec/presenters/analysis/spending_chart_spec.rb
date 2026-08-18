require "rails_helper"

RSpec.describe Analysis::SpendingChart do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:analysis) { Budgeting::YearAnalysis.new(year: 2026, today: Date.new(2026, 7, 15)) }
  let(:config) { described_class.new(analysis).to_config }

  def spend(cents, on:)
    Expense.create!(name: "feira", amount_cents: cents, payment_method: "debit",
                    category: mercado, date: on)
  end

  it "labels the twelve months in Portuguese" do
    expect(config[:data][:labels]).to eq %w[jan fev mar abr mai jun jul ago set out nov dez]
  end

  it "plots each month's spending in reais (AC 2)" do
    spend(5_000, on: Date.new(2026, 3, 4))
    spend(2_550, on: Date.new(2026, 4, 4))

    bars = config[:data][:datasets].first
    expect(bars[:type]).to eq "bar"
    expect(bars[:data][2]).to eq 50.0
    expect(bars[:data][3]).to eq 25.5
    expect(config[:data][:datasets].first[:backgroundColor]).to eq "var(--chart-1)"
  end

  it "leaves months outside the timeline as gaps, not zero bars (AC 9, AC 10)" do
    spend(5_000, on: Date.new(2026, 3, 4))

    bars = config[:data][:datasets].first[:data]
    expect(bars[0]).to be_nil   # January — before the first month
    expect(bars[1]).to be_nil   # February — before the first month
    expect(bars[7]).to be_nil   # August — not yet reached
  end

  it "draws the average as a line over the months that have data only (AC 2)" do
    spend(6_000, on: Date.new(2026, 3, 4))
    spend(4_000, on: Date.new(2026, 4, 4))

    average = config[:data][:datasets].last
    expect(average[:type]).to eq "line"
    # (60 + 40 + 0 + 0 + 0) / 5 active months
    expect(average[:data][2]).to eq 20.0
    expect(average[:data][6]).to eq 20.0
    expect(average[:data][0]).to be_nil
    expect(average[:data][7]).to be_nil
  end

  describe "the empty state" do
    let(:azul) { create_card!(name: "Azul") }

    def filtered_chart(card)
      described_class.new(Budgeting::YearAnalysis.new(year: 2026, card:, today: Date.new(2026, 7, 15)))
    end

    it "reports empty and names the card when that card has no spending (AC 8)" do
      spend(5_000, on: Date.new(2026, 3, 4))

      chart = filtered_chart(azul)
      expect(chart).to be_empty
      expect(chart.empty_message).to eq "Nenhum gasto em Azul em 2026."
    end

    it "reports empty without a card when the year itself has no spending" do
      chart = described_class.new(analysis)
      expect(chart).to be_empty
      expect(chart.empty_message).to eq "Nenhum gasto em 2026."
    end

    it "is not empty once there is spending" do
      spend(5_000, on: Date.new(2026, 3, 4))
      expect(described_class.new(analysis)).not_to be_empty
    end

    it "carries no all-cards note — it is the chart the filter acts on" do
      expect(described_class.new(analysis).note).to be_nil
    end
  end
end
