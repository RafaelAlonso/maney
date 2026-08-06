require "rails_helper"

# `:no_current_user` — this is the one spec that needs a database with nobody in
# it, because that is the state the real migration runs against.
RSpec.describe Users::Claim, :no_current_user do
  let(:march) { Date.new(2026, 3, 1) }

  # `user_id` is NOT NULL on every owned table (Task 5), but this spec has to
  # reproduce the pre-account schema state Users::Claim actually runs against
  # in production: `db:migrate` stops right before that migration, `users:claim`
  # runs while the column is still nullable, then `db:migrate` finishes the job.
  # The test database is always fully migrated, so the constraint is relaxed
  # for the duration of this file only, and restored afterwards.
  around do |example|
    migration = ActiveRecord::Migration.new
    described_class::TABLES.each { |table| migration.change_column_null(table, :user_id, true) }
    example.run
  end

  # No manual restore here: `change_column_null` above runs inside the same
  # per-example transaction rspec-rails opens in `before_setup` (it wraps this
  # `around`, not the other way round — MinitestLifecycleAdapter's own
  # `group.around` is the outer hook), and PostgreSQL DDL is transactional. The
  # `after_teardown` ROLLBACK that ends every example therefore already undoes
  # the relaxation and discards any null-`user_id` rows the example left behind
  # — including the "rolls everything back" example's — with nothing left for
  # this file to clean up by hand.

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

  # I1: the operational trap. An operator who created an account by hand before
  # running `users:claim` — the natural instinct after `db:migrate` stops asking
  # for one — must have a way out that does not require touching the database
  # by hand.
  describe "adopting an existing person" do
    # The `before` above already leaves the database in exactly the state this
    # guards against: fixtures built through a temporary person, then detached
    # and that person destroyed, so every row already sits with a null
    # `user_id` before this example even starts.
    it "adopts the sole existing person and attaches every row to them, leaving their credentials untouched" do
      already_here = User.create!(email_address: "ja-existe@example.com", password: "senha-original")

      result = described_class.new(email_address: "rafael@example.com", password: "outra-senha").call

      expect(result.user).to eq(already_here)
      expect(User.count).to eq(1)
      described_class::TABLES.each do |table|
        model = table.classify.constantize
        expect(model.unscoped.where(user_id: nil).count).to eq(0), "#{table} still has unattached rows"
        expect(model.unscoped.where(user_id: already_here.id).count).to be > 0
      end
      # Adoption must not touch the account it adopts: the password passed to
      # `Claim.new` above ("outra-senha") is only ever used when a person is
      # created, never when one is adopted.
      expect(already_here.authenticate("senha-original")).to be_truthy
      expect(already_here.authenticate("outra-senha")).to be_falsy
    end

    it "still raises AlreadyClaimed with two or more existing people, even though neither owns a row yet" do
      User.create!(email_address: "a@example.com", password: "segredo-de-teste")
      User.create!(email_address: "b@example.com", password: "segredo-de-teste")

      expect { claim }.to raise_error(described_class::AlreadyClaimed)
      expect(User.count).to eq(2)
    end

    it "still raises AlreadyClaimed when the sole existing person already owns rows" do
      already_here = User.create!(email_address: "ja-existe@example.com", password: "senha-original")
      # Only one table is attached to them — the guard must still block the
      # whole claim, not merely skip what's already owned.
      Setting.unscoped.update_all(user_id: already_here.id)

      expect { claim }.to raise_error(described_class::AlreadyClaimed)
      expect(User.count).to eq(1)
    end
  end
end
