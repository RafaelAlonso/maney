require "rails_helper"

RSpec.describe Analysis::CategoryStackChart do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:lazer) { Category.create!(name: "lazer") }
  let(:analysis) { Budgeting::YearAnalysis.new(year: 2026, today: Date.new(2026, 7, 15)) }
  let(:config) { described_class.new(analysis).to_config }

  def spend(cents, on:, category:)
    Expense.create!(name: "gasto", amount_cents: cents, payment_method: "debit", category:, date: on)
  end

  it "stacks both axes" do
    spend(5_000, on: Date.new(2026, 3, 4), category: mercado)

    expect(config[:options][:scales][:x][:stacked]).to be true
    expect(config[:options][:scales][:y][:stacked]).to be true
  end

  it "gives each category its own dataset, ordered by year total with the largest at the base (AC 3)" do
    spend(1_000, on: Date.new(2026, 3, 4), category: lazer)
    spend(9_000, on: Date.new(2026, 4, 4), category: mercado)

    expect(config[:data][:datasets].map { |dataset| dataset[:label] }).to eq [ "mercado", "lazer" ]
  end

  # AC 5: absent, not a zero segment. Chart.js draws nothing for a null.
  it "omits a category from a month it did not touch" do
    spend(9_000, on: Date.new(2026, 4, 4), category: mercado)

    mercado_data = config[:data][:datasets].first[:data]
    expect(mercado_data[3]).to eq 90.0
    expect(mercado_data[2]).to be_nil
  end

  it "still draws a gap for months outside the timeline (AC 9, AC 10)" do
    spend(9_000, on: Date.new(2026, 4, 4), category: mercado)

    mercado_data = config[:data][:datasets].first[:data]
    expect(mercado_data[0]).to be_nil
    expect(mercado_data[11]).to be_nil
  end

  it "never includes the reserved credit-card category (AC 4)" do
    spend(40_000, on: Date.new(2026, 3, 12), category: credit_card_category)
    spend(9_000, on: Date.new(2026, 4, 4), category: mercado)

    expect(config[:data][:datasets].map { |dataset| dataset[:label] }).to eq [ "mercado" ]
  end

  it "keeps a category's colour stable when the year changes" do
    spend(9_000, on: Date.new(2026, 4, 4), category: mercado)
    spend(1_000, on: Date.new(2026, 5, 4), category: lazer)

    colors_2026 = config[:data][:datasets].to_h { |d| [ d[:label], d[:backgroundColor] ] }

    spend(50_000, on: Date.new(2027, 2, 4), category: lazer)
    later = described_class.new(Budgeting::YearAnalysis.new(year: 2027, today: Date.new(2027, 6, 1))).to_config
    colors_2027 = later[:data][:datasets].to_h { |d| [ d[:label], d[:backgroundColor] ] }

    expect(colors_2027["lazer"]).to eq colors_2026["lazer"]
  end

  it "sorts each month's tooltip by that month's own values, descending (AC 3)" do
    expect(config[:options][:plugins][:tooltip][:itemSort]).to eq "desc"
  end
end
