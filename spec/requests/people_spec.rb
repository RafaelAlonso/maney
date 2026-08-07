require "rails_helper"

RSpec.describe "People", type: :request do
  before { create_setting!; create_reserved_categories! }

  # AC 9
  it "lists everyone with their status" do
    Invitation.issue(email_address: "pendente@example.com", invited_by: current_user)
    create_user!(email_address: "ativa@example.com")

    get people_path

    expect(response.body).to include("pendente@example.com", "pendente")
    expect(response.body).to include("ativa@example.com", "ativa")
  end

  # AC 9, and the guardrail: the list holds statuses, never money.
  it "shows no financial value belonging to anyone else" do
    other = create_user!(email_address: "ativa@example.com")
    as(other) do
      create_setting!(initial_balance_cents: 987_654)
      Income.create!(name: "Salário secreto", amount_cents: 1_234_567, date: Date.new(2026, 3, 10))
    end

    get people_path

    expect(response.body).not_to include("Salário secreto")
    expect(response.body).not_to include("9.876,54")
    expect(response.body).not_to include("12.345,67")
  end

  it "is unreachable for someone who is not Rafael" do
    sign_out_request
    sign_in(create_user!(email_address: "irma@example.com"))
    authenticate_request

    get people_path

    expect(response).to redirect_to(root_path)
  end

  it "is linked from Config for Rafael and nobody else" do
    get edit_settings_path
    expect(response.body).to include(people_path)

    sign_out_request
    sign_in(create_user!(email_address: "irma@example.com"))
    authenticate_request
    as(current_user) { create_setting!; create_reserved_categories! }

    get edit_settings_path
    expect(response.body).not_to include(people_path)
  end
end
