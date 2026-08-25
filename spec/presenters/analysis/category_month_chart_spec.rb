require "rails_helper"

RSpec.describe Analysis::CategoryMonthChart do
  let(:march) { Date.new(2026, 3, 1) }
  before { create_setting!(first_month: march); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:casa) { Category.create!(name: "casa") }
  let(:lazer) { Category.create!(name: "lazer") }
  let(:summary) { Budgeting::MonthSummary.new(month: march, today: Date.new(2026, 3, 15)) }
  let(:categories) { Category.order(:name).to_a }

  def spend(cents, on: mercado, date: Date.new(2026, 3, 5))
    Expense.create!(name: "gasto", amount_cents: cents, payment_method: "debit", category: on, date:)
  end

  def config = described_class.new(summary:, categories:).to_config

  it "titles the chart with the month in context" do
    expect(described_class.new(summary:, categories:).title).to eq "Gastos por categoria em 03/2026"
  end

  it "plots one bar per spending category, most expensive first, in reais" do
    spend(50_000, on: mercado)
    spend(120_000, on: casa)
    spend(30_000, on: lazer)

    expect(config[:data][:labels]).to eq %w[casa mercado lazer]
    expect(config[:data][:datasets].first[:data]).to eq [ 1200.0, 500.0, 300.0 ]
  end

  it "omits a category with nothing spent this month" do
    spend(50_000, on: mercado)

    expect(config[:data][:labels]).to eq %w[mercado]
  end

  it "excludes the reserved credit-card category so credit spending is not counted twice" do
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 40_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card:, category: mercado)
    # A statement payment lands on the credit-card category in the same month.
    Expense.create!(name: "fatura", amount_cents: 40_000, date: Date.new(2026, 3, 12),
                    payment_method: "debit", category: credit_card_category)

    expect(config[:data][:labels]).to eq %w[mercado]
  end

  it "gives each bar its category's theme-aware chart var" do
    spend(50_000, on: mercado)
    colors = config[:data][:datasets].first[:backgroundColor]
    expect(colors.first).to match(/\Avar\(--chart-\d+\)\z/)
  end

  it "is empty when nothing was spent" do
    expect(described_class.new(summary:, categories:).any?).to be false
  end
end
