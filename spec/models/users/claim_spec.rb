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
  ensure
    # The "rolls everything back" example deliberately leaves rows with a null
    # user_id sitting in an open transaction — restoring NOT NULL would fail on
    # exactly the data this file exists to create. Transactional fixtures clean
    # that up on rollback, but only once this hook returns, so the delete here
    # is what actually makes the column change_column_null-safe again; whatever
    # a successful claim already reattached is untouched (no null rows left).
    #
    # The restore gets its own `ensure` on purpose: this outer `around` sits
    # *inside* rspec-rails's own `around` (MinitestLifecycleAdapter wraps
    # `before_setup; example.run; after_teardown` around every example group's
    # hooks), so an exception escaping here — e.g. the DELETE raising, which
    # has already happened once in this file's history as an uncaught
    # PG::ForeignKeyViolation, or disable_referential_integrity re-raising
    # ActiveRecord::InvalidForeignKey if the connection's role can't disable
    # triggers — would skip `after_teardown` entirely, i.e. skip the ROLLBACK,
    # leaving the column nullable and the transaction abandoned for the rest
    # of the process. Nesting the restore in its own `ensure` means it always
    # attempts to run, independent of whether the cleanup above succeeded.
    begin
      # A savepoint, not a bare call: if the DELETE raises mid-way (it has,
      # historically — an uncaught PG::ForeignKeyViolation), an exception
      # inside a plain Postgres statement leaves the whole surrounding
      # transaction ABORTED, and every statement after it — including the
      # restore below — is rejected with "current transaction is aborted"
      # rather than actually running. `requires_new: true` opens a SAVEPOINT,
      # so a failure here only rolls back to that savepoint and leaves the
      # outer (per-example) transaction healthy for the restore to run in.
      ActiveRecord::Base.transaction(requires_new: true) do
        ActiveRecord::Base.connection.disable_referential_integrity do
          described_class::TABLES.each { |table| ActiveRecord::Base.connection.execute(%(DELETE FROM "#{table}" WHERE user_id IS NULL)) }
        end
      end
    ensure
      # Known accepted gap, verified by a scratch experiment (forcing a raise
      # inside the block above, then reverting it — see the Task 5 fix report):
      # if the DELETE fails so completely that no row anywhere gets cleaned
      # (e.g. disable_referential_integrity itself refuses before touching any
      # table), this restore call is genuinely unable to succeed — you cannot
      # make a column NOT NULL over rows that are still null, savepoint or not.
      # That failure then escapes this `ensure`, and because
      # MinitestLifecycleAdapter's around calls `after_teardown` as plain
      # sequential code (no rescue), the per-example ROLLBACK never runs,
      # leaking an aborted transaction into every later example on this
      # connection for the rest of the process. Living with that risk rests on
      # two assumptions holding in every environment this suite runs in: the
      # Postgres role owns these tables (so disabling triggers cannot itself
      # be refused for lack of privilege), and the FK graph among the eight
      # TABLES stays what FINGERPRINT already documents (so ordering doesn't
      # regress the ForeignKeyViolation this method was written to prevent).
      described_class::TABLES.each { |table| migration.change_column_null(table, :user_id, false) }
    end
  end

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
