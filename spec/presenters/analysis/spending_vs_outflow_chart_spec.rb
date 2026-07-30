require "rails_helper"

RSpec.describe Analysis::SpendingVsOutflowChart do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:card) { create_card! }
  let(:analysis) { Budgeting::YearAnalysis.new(year: 2026, today: Date.new(2026, 7, 15)) }
  let(:config) { described_class.new(analysis).to_config }

  before do
    Expense.create!(name: "feira", amount_cents: 30_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 6))
    Expense.create!(name: "tv", amount_cents: 150_000, payment_method: "credit",
                    category: mercado, card:, date: Date.new(2026, 3, 7))
    Expense.create!(name: "fatura", amount_cents: 20_000, payment_method: "debit",
                    category: credit_card_category, date: Date.new(2026, 3, 12))
  end

  it "shows the two figures side by side, not stacked (AC 8)" do
    labels = config[:data][:datasets].map { |dataset| dataset[:label] }

    expect(labels).to eq [ "Gastos", "Saídas" ]
    expect(config[:options][:scales][:x][:stacked]).to be_falsey
  end

  it "measures spending by competence and outflow by what left the account" do
    spending, outflow = config[:data][:datasets]

    # Spending: R$ 300 debit + R$ 1.500 credit, statement payment excluded.
    expect(spending[:data][2]).to eq 1_800.0
    # Outflow: R$ 300 debit + R$ 200 statement payment, credit excluded.
    expect(outflow[:data][2]).to eq 500.0
  end

  it "leaves months outside the timeline as gaps (AC 9, AC 10)" do
    expect(config[:data][:datasets].first[:data][0]).to be_nil
    expect(config[:data][:datasets].last[:data][7]).to be_nil
  end
end
