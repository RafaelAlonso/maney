require "rails_helper"

# `:no_current_user` — this is the one spec that needs a database with nobody in
# it, because that is the state the real migration runs against.
RSpec.describe Users::Claim, :no_current_user do
  let(:march) { Date.new(2026, 3, 1) }

  # Builds the pre-account database: rows that exist and belong to nobody. They
  # have to be created through a temporary person (OwnedByUser requires one),
  # then detached and the person removed.
  before do
    builder = User.create!(email_address: "temp@example.com", password: "segredo-de-teste")
    Current.session = Session.create!(user: builder)

    create_setting!(first_month: march, initial_balance_cents: 100_000)
    create_reserved_categories!
    mercado = Category.create!(name: "mercado")
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Expense.create!(name: "feira", amount_cents: 100_000, date: Date.new(2026, 3, 5),
                    payment_method: "debit", category: mercado)
    Budget.create!(category: mercado, month: march, amount_cents: 400_000)
    card = create_card!
    InstallmentPurchase.create!(name: "notebook", total_cents: 200_000, installments_count: 2,
                                first_installment: 1, date: march, card:, category: mercado)

    Current.session = nil
    described_class::TABLES.each { |table| table.classify.constantize.unscoped.update_all(user_id: nil) }
    builder.destroy!
  end

  def claim = described_class.new(email_address: "rafael@example.com", password: "segredo-de-teste").call

  it "attaches every existing row to the new person" do
    result = claim

    described_class::TABLES.each do |table|
      model = table.classify.constantize
      expect(model.unscoped.where(user_id: nil).count).to eq(0), "#{table} still has unattached rows"
      expect(model.unscoped.count).to be > 0
    end
    expect(result.rows_attached).to eq(described_class::TABLES.sum { |t| t.classify.constantize.unscoped.count })
  end

  it "leaves the month's figures exactly as they were (AC 7)" do
    user = claim.user
    Current.session = Session.create!(user:)

    summary = Budgeting::MonthSummary.new(month: march)

    # 100.000 initial + 500.000 income − 100.000 debit = 500.000
    expect(summary.current_balance_cents).to eq(500_000)
    expect(Setting.instance.first_month).to eq(march)
    expect(Category.count).to eq(3)
    expect(Card.count).to eq(1)
  end

  it "refuses to run a second time" do
    claim

    expect { claim }.to raise_error(described_class::AlreadyClaimed)
    expect(User.count).to eq(1)
  end

  it "rolls everything back when a row would be left behind" do
    stub_const("#{described_class}::TABLES", described_class::TABLES - [ "incomes" ])

    expect { claim }.to raise_error(described_class::Tampered)

    expect(User.count).to eq(0)
    expect(Category.unscoped.where(user_id: nil).count).to be > 0
  end
end
