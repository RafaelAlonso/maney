require "rails_helper"

RSpec.describe Analysis::CategorySpendingChart do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:category_year) { Budgeting::CategoryYear.new(category: mercado, year: 2026, today: Date.new(2026, 7, 15)) }
  let(:config) { described_class.new(category_year).to_config }

  def spend(cents, on:)
    Expense.create!(name: "feira", amount_cents: cents, payment_method: "debit",
                    category: mercado, date: on)
  end

  it "names the year in the title, since the screen has no year picker" do
    expect(described_class.new(category_year).title).to eq "Gastos por mês em 2026"
  end

  it "labels the twelve months in Portuguese" do
    expect(config[:data][:labels]).to eq %w[jan fev mar abr mai jun jul ago set out nov dez]
  end

  it "plots the category's monthly totals in reais (AC 1)" do
    spend(5_000, on: Date.new(2026, 3, 4))
    spend(2_550, on: Date.new(2026, 4, 4))

    bars = config[:data][:datasets].first
    expect(bars[:type]).to eq "bar"
    expect(bars[:data][2]).to eq 50.0
    expect(bars[:data][3]).to eq 25.5
  end

  it "draws the average over the months that have data only (AC 1, AC 7)" do
    spend(6_000, on: Date.new(2026, 3, 4))
    spend(4_000, on: Date.new(2026, 4, 4))

    average = config[:data][:datasets].last
    expect(average[:type]).to eq "line"
    # (60 + 40 + 0 + 0 + 0) / 5 active months, March through July.
    expect(average[:data][2]).to eq 20.0
    expect(average[:data][0]).to be_nil   # before the first month
    expect(average[:data][7]).to be_nil   # not yet reached
  end

  it "leaves months outside the timeline as gaps, not zero bars (AC 7)" do
    spend(5_000, on: Date.new(2026, 3, 4))

    bars = config[:data][:datasets].first[:data]
    expect(bars[0]).to be_nil
    expect(bars[1]).to be_nil
    expect(bars[7]).to be_nil
  end

  # The guardrail restated at the presenter level: same bars, same average, same
  # chrome as the year screen — only the title differs.
  it "emits the same config as the year chart would for the same series" do
    spend(5_000, on: Date.new(2026, 3, 4))
    year = Budgeting::YearAnalysis.new(year: 2026, today: Date.new(2026, 7, 15))

    expect(config[:data]).to eq Analysis::SpendingChart.new(year).to_config[:data]
  end

  # CategoryYear defines no `filtered?` and no `card`: the inherited
  # SpendingChart#empty? predicate would reach `analysis.filtered?` through
  # empty_message and raise. This chart overrides both empty? and
  # empty_message so a zero-spending category-year never crashes.
  it "never reports empty, even with no spending, and does not crash if empty_message is reached anyway" do
    chart = described_class.new(category_year)

    expect(chart.empty?).to be false
    expect { chart.empty_message }.not_to raise_error
  end
end
