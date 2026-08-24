require "rails_helper"

RSpec.describe "Settings", type: :request do
  before { create_setting!(initial_balance_cents: 10_000); create_reserved_categories! }

  it "shows the current settings values (AC 12/18)" do
    get edit_settings_path
    expect(response.body).to include("2026-03").and include("100,00")
    # The reserved-category section was removed entirely — no list, no forms.
    expect(response.body).not_to include("Categorias reservadas")
    expect(response.body).not_to include("Renomear")
  end

  it "updates first month and initial balance (AC 18)" do
    patch settings_path, params: { setting: { first_month: "2026-02", initial_balance: "-250,00", alert_threshold_percent: "80" } }
    expect(Setting.instance.first_month).to eq Date.new(2026, 2, 1)
    expect(Setting.instance.initial_balance_cents).to eq(-25_000)
  end

  it "refuses moving first month after existing entries (engine rule)" do
    Income.create!(name: "salário", amount_cents: 100, date: Date.new(2026, 3, 1))
    patch settings_path, params: { setting: { first_month: "2026-04", initial_balance: "100,00" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Setting.instance.first_month).to eq Date.new(2026, 3, 1)
  end

  it "rejects an unparseable initial balance without silently zeroing it" do
    patch settings_path, params: { setting: { first_month: "2026-03", initial_balance: "abc" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
    expect(Setting.instance.initial_balance_cents).to eq 10_000
  end

  it "rejects a blank initial balance without silently zeroing it" do
    patch settings_path, params: { setting: { first_month: "2026-03", initial_balance: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
    expect(Setting.instance.initial_balance_cents).to eq 10_000
  end

  it "accepts a legitimate zero initial balance" do
    patch settings_path, params: { setting: { first_month: "2026-03", initial_balance: "0,00", alert_threshold_percent: "80" } }
    expect(response).to redirect_to(edit_settings_path)
    expect(Setting.instance.initial_balance_cents).to eq 0
  end

  it "does not partially apply a valid first_month when the initial balance is unparseable" do
    patch settings_path, params: { setting: { first_month: "2026-02", initial_balance: "abc" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Setting.instance.first_month).to eq Date.new(2026, 3, 1)
    expect(Setting.instance.initial_balance_cents).to eq 10_000
  end

  it "persists a valid alert threshold" do
    patch settings_path, params: { setting: { first_month: "2026-03", initial_balance: "100,00", alert_threshold_percent: "90" } }
    expect(response).to redirect_to(edit_settings_path)
    expect(Setting.instance.alert_threshold_percent).to eq(90)
  end

  it "rejects a threshold outside 1..100" do
    patch settings_path, params: { setting: { first_month: "2026-03", initial_balance: "100,00", alert_threshold_percent: "150" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Setting.instance.alert_threshold_percent).to eq(80)
  end

  # Finding 1: the admin has no way to lose the account that invites, so the
  # link to a path that would try is hidden — the link and the guard behind
  # it (see account_deletions_spec) have to agree.
  it "hides the deletion link for the admin but shows it for a member" do
    get edit_settings_path
    expect(response.body).not_to include(new_account_deletion_path)

    irma = create_user!(email_address: "irma@example.com")
    sign_out_request
    sign_in(irma)
    authenticate_request
    as(irma) { create_setting!; create_reserved_categories! }

    get edit_settings_path
    expect(response.body).to include(new_account_deletion_path)
  end

  it "renders the settings form in the design system (AC 6)" do
    get edit_settings_path

    expect(response.body).to include("btn btn-primary")
    expect(response.body).to include("field-input")
    expect(response.body).not_to include("bg-blue-600")
  end
end
