require "rails_helper"

RSpec.describe Analysis::ProfitChart do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:card) { create_card! }
  let(:analysis) { Budgeting::YearAnalysis.new(year: 2026, today: Date.new(2026, 7, 15)) }
  let(:chart) { described_class.new(analysis) }

  before do
    Income.create!(name: "salário", amount_cents: 100_000, date: Date.new(2026, 3, 5))
    Expense.create!(name: "feira", amount_cents: 30_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 6))
    Expense.create!(name: "tv", amount_cents: 150_000, payment_method: "credit",
                    category: mercado, card:, date: Date.new(2026, 3, 7))
    # An income-only month (no expenses at all): a genuine positive profit,
    # distinct from April's break-even zero, so the colour test below cannot
    # be satisfied by a design that only distinguishes negative from zero.
    Income.create!(name: "bônus", amount_cents: 50_000, date: Date.new(2026, 5, 10))
  end

  it "offers the three modes (AC 6)" do
    expect(chart.modes.keys).to contain_exactly("spending", "outflow", "both")
    expect(chart.mode_labels.map(&:last)).to eq [ "Ganhos − gastos", "Ganhos − saídas", "Os dois" ]
  end

  it "opens on income minus spending" do
    expect(chart.to_config[:data][:datasets].map { |d| d[:label] }).to eq [ "Ganhos − gastos" ]
    expect(chart.to_config[:data][:datasets].first[:data][2]).to eq(-800.0)
  end

  it "reports income minus cash outflow in the outflow mode" do
    expect(chart.modes["outflow"].first[:data][2]).to eq 700.0
  end

  it "shows both series together in the both mode" do
    expect(chart.modes["both"].map { |d| d[:label] }).to eq [ "Ganhos − gastos", "Ganhos − saídas" ]
  end

  # Both series share the same sign palette, so colour alone cannot tell them
  # apart — "Ganhos − gastos" stays filled and "Ganhos − saídas" renders as a
  # transparent-fill outline instead, so a rendered attribute must differ.
  it "renders the two series in the both mode as fill vs outline, not just by colour" do
    spending_series, outflow_series = chart.modes["both"]

    expect(spending_series[:backgroundColor]).to be_an(Array)
    expect(outflow_series[:backgroundColor]).to eq "transparent"
    expect(outflow_series[:borderColor]).to be_an(Array)
    expect(outflow_series[:borderWidth]).to eq 2
  end

  # AC 7: a negative month must be distinguishable at a glance, so the colour is
  # decided per bar in Ruby rather than by a Chart.js callback. Three cases are
  # checked, not two: a genuinely negative month (March), a genuinely positive
  # month (May, income-only), and a break-even month (April, exactly zero) —
  # without May, a design that colours only strictly-positive months green and
  # leaves break-even neutral would still pass.
  it "colours a negative month differently from a positive or break-even one" do
    colors = chart.modes["spending"].first[:backgroundColor]

    expect(colors[2]).to eq Analysis::Palette::NEGATIVE
    expect(colors[3]).to eq Analysis::Palette::POSITIVE
    expect(colors[4]).to eq Analysis::Palette::POSITIVE
  end

  it "leaves months outside the timeline as gaps (AC 9, AC 10)" do
    data = chart.to_config[:data][:datasets].first[:data]

    expect(data[0]).to be_nil
    expect(data[7]).to be_nil
  end
end
