require "rails_helper"

RSpec.describe Analysis::CategoryBreakdownChart do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }
  let(:march) { Date.new(2026, 3, 1) }

  def spend(cents, name: "feira", on: Date.new(2026, 3, 10))
    Expense.create!(name:, amount_cents: cents, payment_method: "debit", category: mercado, date: on)
  end

  def breakdown(month: march)
    described_class.new(expenses: Budgeting::MonthEntries.expenses(month:, category: mercado),
                        category: mercado, month:)
  end

  it "names the month in the title" do
    expect(breakdown.title).to eq "Composição de 03/2026"
  end

  it "lists each expense with its amount and its share of the category's month (AC 3)" do
    spend(48_000, name: "mercado extra")
    spend(22_000, name: "padaria")
    spend(20_000, name: "feira livre")

    slices = breakdown.slices
    expect(slices.map(&:name)).to eq [ "mercado extra", "padaria", "feira livre" ]
    expect(slices.map(&:amount_cents)).to eq [ 48_000, 22_000, 20_000 ]
    expect(slices.map(&:share_percent)).to eq [ 53, 24, 22 ]
  end

  it "shows a single expense at 100%" do
    spend(7_500)

    expect(breakdown.slices.map(&:share_percent)).to eq [ 100 ]
  end

  it "breaks ties on the name, so the order never wobbles" do
    spend(1_000, name: "zebra")
    spend(1_000, name: "abacaxi")

    expect(breakdown.slices.map(&:name)).to eq [ "abacaxi", "zebra" ]
  end

  it "shows every expense, with no other-bucketing" do
    12.times { |index| spend(1_000 + index, name: "gasto #{index}") }

    expect(breakdown.slices.size).to eq 12
    expect(breakdown.slices.map(&:color).uniq.size).to eq 12
  end

  it "lists an installment under its numbered name, at its own amount (AC 6)" do
    InstallmentPurchase.create!(name: "sofá", total_cents: 90_000, installments_count: 3,
                                card: create_card!, category: mercado, date: Date.new(2026, 3, 10))

    slice = breakdown.slices.find { |candidate| candidate.name.start_with?("sofá") }
    expect(slice.name).to eq "sofá 1/3"
    expect(slice.amount_cents).to eq 30_000
    expect(breakdown(month: Date.new(2026, 4, 1)).slices.map(&:name)).to eq [ "sofá 2/3" ]
  end

  it "is empty for a month with no expenses (AC 4)" do
    spend(5_000, on: Date.new(2026, 3, 10))

    subject = breakdown(month: Date.new(2026, 4, 1))
    expect(subject).not_to be_any
    expect(subject.slices).to eq []
  end

  it "shades the slices from the category's own colour, darkest first" do
    spend(9_000, name: "grande")
    spend(1_000, name: "pequeno")

    expect(breakdown.slices.first.color).to eq Analysis::Palette.new.color_for(mercado)
    expect(breakdown.slices.map(&:color).uniq.size).to eq 2
  end

  it "emits a pie config whose data are the amounts in reais, largest first" do
    spend(48_000, name: "mercado extra")
    spend(22_000, name: "padaria")

    config = breakdown.to_config
    expect(config[:type]).to eq "pie"
    expect(config[:data][:labels]).to eq [ "mercado extra", "padaria" ]
    expect(config[:data][:datasets].first[:data]).to eq [ 480.0, 220.0 ]
    # The HTML legend below the canvas carries the values, so Chart.js's own is off.
    expect(config[:options][:plugins][:legend][:display]).to be false
    # A pie has no value axis; leaving scales out keeps chart_controller from
    # building one.
    expect(config[:options]).not_to have_key(:scales)
  end

  # The pie must never disagree with the bar above it or the list below it.
  it "totals to the bar chart's value for that month" do
    spend(48_000, name: "mercado extra")
    spend(22_000, name: "padaria")
    InstallmentPurchase.create!(name: "sofá", total_cents: 90_000, installments_count: 3,
                                card: create_card!, category: mercado, date: Date.new(2026, 3, 10))

    bar = Budgeting::CategoryYear.new(category: mercado, year: 2026, today: Date.new(2026, 7, 15))
    expect(breakdown.total_cents).to eq bar.spending.cents(march)
  end
end
