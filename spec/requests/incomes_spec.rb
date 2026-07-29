require "rails_helper"

RSpec.describe "Incomes", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(initial_balance_cents: 10_000); create_reserved_categories! }

  it "creates an income (AC 3)" do
    post incomes_path, params: { income: { name: "salário", amount: "5.000,00", date: "2026-03-01" } }
    expect(Income.find_by(name: "salário").amount_cents).to eq 500_000
  end

  it "lists the month's incomes with the derived carried balance first (AC 18)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 4, 1))
    get incomes_path(month: "2026-04")
    expect(response.body).to include("saldo do mês anterior").and include("salário")
    expect(response.body.index("saldo do mês anterior")).to be < response.body.index("salário")
  end

  it "labels the first month's derived row as 'saldo inicial' with a link to settings (AC 18)" do
    get incomes_path(month: "2026-03")
    expect(response.body).to include("saldo inicial").and include(edit_settings_path)
  end

  # The derived row lives in the same <ul> as the real incomes, and the examples
  # above only look at text and order — they'd pass just the same if it were
  # rendered as an editable income. The balance is derived from the chain, not an
  # entry: it must be impossible to edit or delete, otherwise the user tries to
  # "fix" a number that no database row produces.
  it "renders the derived row with no way to act on it as an income (AC 18)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 4, 1))
    income = Income.create!(name: "extra", amount_cents: 1_000, date: Date.new(2026, 4, 2))
    get incomes_path(month: "2026-04")

    derived, *real_rows = response.body.split(%(<li class=")).drop(1)
    expect(derived).to include("saldo do mês anterior")
    expect(derived).not_to include("excluir")
    expect(derived).not_to include(edit_income_path(income))
    expect(derived).not_to match(%r{/incomes/\d+})
    # and the contrast: a real income has both controls
    expect(real_rows.join).to include("excluir").and include(edit_income_path(income))
  end

  it "shows a negative carried balance as negative (AC 18)" do
    Setting.instance.update!(initial_balance_cents: -25_000)
    get incomes_path(month: "2026-03")
    expect(response.body).to include("-R$ 250,00")
  end

  it "rejects invalid amounts (AC 14)" do
    post incomes_path, params: { income: { name: "x", amount: "0,00", date: "2026-03-01" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  # Fix 3 (final review pass): every other money surface in the wave (see
  # CategoriesController#save_budget, ExpenseEntry#amount_must_parse) parses
  # first, remaps the model's error onto the field the form actually shows,
  # and re-renders with what the user typed. Incomes did neither: an
  # unparseable amount fell through to `amount_cents: nil`, and Income's own
  # numericality validation fired on the DB column — "Amount cents is not a
  # number" — with the field re-rendered blank, throwing away the input.
  describe "money-input parity with the rest of the wave (Fix 3)" do
    it "rejects an unparseable amount with a Portuguese message on the visible field, preserving the typed value" do
      post incomes_path, params: { income: { name: "salário", amount: "abc", date: "2026-03-01" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("não é um valor válido")
      expect(response.body).not_to include("Amount cents")
      expect(response.body).to include('value="abc"')
      expect(Income.find_by(name: "salário")).to be_nil
    end

    it "still rejects a parsed-but-non-positive amount via Income's own validation, on the visible field" do
      post incomes_path, params: { income: { name: "salário", amount: "0,00", date: "2026-03-01" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include("Amount cents")
      expect(response.body).to include('value="0,00"')
    end

    it "preserves the typed value across a 422 on update too" do
      income = Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))
      patch income_path(income), params: { income: { name: "salário", amount: "xyz", date: "2026-03-01" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("não é um valor válido")
      expect(response.body).to include('value="xyz"')
      expect(income.reload.amount_cents).to eq 500_000
    end
  end

  it "blocks dates before the first month (AC 19)" do
    post incomes_path, params: { income: { name: "x", amount: "10,00", date: "2026-02-01" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("primeiro mês")
  end

  it "updates and destroys a real income" do
    income = Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))
    patch income_path(income), params: { income: { name: "salário líquido", amount: "4.800,00", date: "2026-03-01" } }
    expect(income.reload.amount_cents).to eq 480_000
    delete income_path(income)
    expect(Income.exists?(income.id)).to be false
  end

  # The list showed the entries but no total, so the month's income was displayed
  # nowhere in the app. The carried balance counts, exactly as it does in the
  # month view's block — the two screens must show the same number.
  it "totals the month's income including the carried balance" do
    Setting.instance.update!(initial_balance_cents: 200_000)
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))

    get incomes_path(month: "2026-03")

    expect(response.body).to include("total")
    expect(response.body).to include("R$ 7.000,00")
  end

  it "returns to the month the list was showing after a delete" do
    income = Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))

    delete income_path(income, month: "2026-03")

    expect(response).to redirect_to(incomes_path(month: "2026-03"))
  end

  it "starts a new income on the 1st of the month being viewed" do
    travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
      get new_income_path(month: "2026-03")

      expect(response.body).to include('value="2026-03-01"')
    end
  end
end
