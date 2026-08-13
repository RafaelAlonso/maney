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

  # Guards the ordering fix from this task's review: `require_admin` must run
  # ahead of `require_setup` (the assertion above), but not ahead of
  # `require_authentication` — a signed-out visitor belongs at the sign-in
  # screen — and `require_setup` must still gate Rafael himself.
  it "sends a signed-out visitor to the sign-in screen rather than treating them as a non-admin" do
    sign_out_request

    get people_path

    expect(response).to redirect_to(new_session_path)
  end

  it "still sends an admin who has not completed setup to /setup" do
    sign_out_request
    sign_in(create_user!(email_address: "novo-admin@example.com", admin: true))
    authenticate_request

    get people_path

    expect(response).to redirect_to(setup_path)
  end

  # Finding 5: "Excluir" on an already-deleted person resets their 30-day
  # erasure clock (delete_account! sets deleted_at: Time.current again), and
  # "Revogar" on one leaves them unrestorable until access is restored first.
  # The status still has to show — only the buttons go.
  it "offers no destructive action for a deleted person's row" do
    irma = create_user!(email_address: "irma@example.com")
    irma.delete_account!

    get people_path

    expect(response.body).to include("irma@example.com")
    expect(response.body).not_to include(person_path(irma))
    expect(response.body).not_to include(person_access_path(irma))
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
