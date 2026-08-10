require "rails_helper"
require "rake"

# The fingerprint is only worth anything if it is deterministic and complete:
# a report that silently omits a user, or reports an empty database because
# nobody is signed in, would make a failed restore look like a passing one.
RSpec.describe "db:fingerprint", :no_current_user do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("db:fingerprint")
  end

  def fingerprint_lines
    task = Rake::Task["db:fingerprint"]
    task.reenable
    original = $stdout
    $stdout = StringIO.new
    task.invoke
    $stdout.string.lines.map(&:rstrip)
  ensure
    $stdout = original
  end

  def create_user!(email_address)
    User.create!(email_address:, password: "segredo-de-teste")
  end

  def as(user)
    Current.set(session: Session.new(user:)) { yield }
  end

  # The per-user half of the report, up to where the global table sections begin.
  def user_lines
    fingerprint_lines.take_while { |line| !line.start_with?("table ") }
  end

  # A user whose whole visible timeline is 2026-01..08 — so an installment
  # falling due later lands in a month the per-month lines never print.
  def scenario_user(email_address = "rafael@example.com")
    user = create_user!(email_address)
    as(user) do
      Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
      category = Category.create!(name: "casa")
      card = Card.create!(name: "nubank")
      card.card_schedules.create!(closing_day: 5, due_day: 12, valid_from: Date.new(2026, 1, 1))
      (1..8).each do |month|
        Income.create!(name: "salário", date: Date.new(2026, month, 5), amount_cents: 500_000)
      end
      yield(user:, card:, category:) if block_given?
    end
    Current.session = nil
    user
  end

  it "reports every user in email order, counting only that user's rows" do
    ana = create_user!("ana@example.com")
    rafael = create_user!("rafael@example.com")

    as(rafael) do
      Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 10_000)
      Income.create!(name: "salário", date: Date.new(2026, 1, 5), amount_cents: 50_000)
    end
    as(ana) do
      Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
    end

    Current.session = nil

    expect(user_lines).to eq([
      "user ana@example.com",
      "  cards=0 categories=0 incomes=0 expenses=0 installment_purchases=0",
      "user rafael@example.com",
      "  cards=0 categories=0 incomes=1 expenses=0 installment_purchases=0",
      "  2026-01 incomes_total=60000 current_balance=60000 estimated_balance=60000"
    ])
  end

  it "reports a month for every month holding an entry, and only those" do
    rafael = create_user!("rafael@example.com")

    as(rafael) do
      Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
      category = Category.create!(name: "mercado")
      Income.create!(name: "salário", date: Date.new(2026, 1, 5), amount_cents: 50_000)
      Expense.create!(name: "feira", category:, payment_method: "debit",
                      date: Date.new(2026, 3, 10), amount_cents: 20_000)
    end

    Current.session = nil

    months = fingerprint_lines.grep(/^  \d{4}-\d{2} /).map { |line| line.split.first }
    expect(months).to eq(%w[2026-01 2026-03])
  end

  it "ignores whoever happens to be signed in when it runs" do
    ana = create_user!("ana@example.com")
    rafael = create_user!("rafael@example.com")

    as(rafael) do
      Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
      Income.create!(name: "salário", date: Date.new(2026, 1, 5), amount_cents: 50_000)
    end

    # A stale current user must not scope the report. Without the per-user
    # wrapping in the task, this reports ana's empty database for everyone.
    Current.session = Session.create!(user: ana)

    expect(fingerprint_lines).to include(
      "  cards=0 categories=0 incomes=1 expenses=0 installment_purchases=0"
    )
  end

  it "emits only lines bin/restore-drill can filter" do
    scenario_user

    expect(fingerprint_lines.grep_v(/\A(user |table |  )/)).to be_empty
  end

  # What follows pins the report's *sensitivity*, not its wording: a restore that
  # altered any of these values must not be able to produce the same bytes. Each
  # example compares a before and an after, so it keeps holding when the output
  # grammar changes.
  describe "sensitivity to a corrupted restore" do
    it "changes when an installment amount changes in a month holding nothing else" do
      scenario_user do |card:, category:, **|
        InstallmentPurchase.create!(name: "sofá", card:, category:,
                                    date: Date.new(2026, 8, 20),
                                    total_cents: 120_000, installments_count: 12)
      end

      before = fingerprint_lines
      # The installments fall due 2026-09..2027-08: months with no income and no
      # dated expense, so no per-month line ever reaches them.
      expect(before.grep(/^  (2026-09|2027-)/)).to be_empty

      InstallmentPurchase.unscoped.update_all(total_cents: 240_000)
      Expense.unscoped.where.not(installment_purchase_id: nil).update_all("amount_cents = amount_cents * 2")

      expect(fingerprint_lines).not_to eq(before)
    end

    it "changes when a budget amount changes" do
      user = scenario_user
      # 2027-03 holds no income and no dated expense, so the per-month lines
      # never visit it — only a budgets aggregate can see this row.
      as(user) { Budget.create!(category: Category.sole, month: Date.new(2027, 3, 1), amount_cents: 30_000) }
      Current.session = nil

      before = fingerprint_lines
      Budget.unscoped.update_all(amount_cents: 90_000)

      expect(fingerprint_lines).not_to eq(before)
    end

    it "changes when a card's closing day changes" do
      scenario_user

      before = fingerprint_lines
      CardSchedule.unscoped.update_all(closing_day: 20)

      expect(fingerprint_lines).not_to eq(before)
    end

    it "changes when a password digest changes, without printing it" do
      user = scenario_user

      before = fingerprint_lines
      digest = User.unscoped.where(id: user.id).pick(:password_digest)
      expect(before.join("\n")).not_to include(digest)

      user.update!(password: "outro-segredo-de-teste")

      after = fingerprint_lines
      expect(after).not_to eq(before)
      expect(after.join("\n")).not_to include(user.reload.password_digest)
    end

    it "changes when a card, category or setting is renamed or retuned" do
      user = scenario_user

      before = fingerprint_lines
      Card.unscoped.update_all(name: "outro cartão")
      expect(fingerprint_lines).not_to eq(before)

      renamed = fingerprint_lines
      Category.unscoped.update_all(name: "outra categoria", role: "credit_card")
      expect(fingerprint_lines).not_to eq(renamed)

      recategorised = fingerprint_lines
      Setting.unscoped.where(user_id: user.id).update_all(alert_threshold_percent: 55)
      expect(fingerprint_lines).not_to eq(recategorised)
    end
  end
end
