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

    expect(fingerprint_lines).to eq([
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
end
