require "rails_helper"

RSpec.describe "Setup", type: :request do
  it "redirects any page to setup when there is no Setting" do
    get root_path
    expect(response).to redirect_to(setup_path)
  end

  it "creates the Setting and the reserved categories" do
    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "1.234,56" } }
    expect(response).to redirect_to(root_path)
    expect(Setting.instance.first_month).to eq Date.new(2026, 3, 1)
    expect(Setting.instance.initial_balance_cents).to eq 123_456
    expect(Category.find_by(role: "others").name).to eq "outros"
    expect(Category.find_by(role: "credit_card").name).to eq "cartão de crédito"
  end

  it "re-renders with errors on invalid input" do
    post setup_path, params: { setup: { first_month: "", initial_balance: "0,00" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "redirects setup back to home when already configured" do
    Setting.create!(first_month: Date.new(2026, 3, 1))
    get setup_path
    expect(response).to redirect_to(root_path)
  end
end
