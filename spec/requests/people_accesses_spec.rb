require "rails_helper"

RSpec.describe "Revoking access", type: :request do
  before { create_setting!; create_reserved_categories! }

  let(:irma) { create_user!(email_address: "irma@example.com") }

  # AC 10
  it "blocks sign-in and erases nothing" do
    as(irma) { create_setting!; Income.create!(name: "Salário", amount_cents: 100_00, date: Date.new(2026, 3, 5)) }

    delete person_access_path(irma)

    expect(irma.reload).to be_access_revoked
    expect(Income.unscoped.where(user_id: irma.id).count).to eq(1)

    sign_out_request
    post session_path, params: { email_address: "irma@example.com", password: AuthenticationHelpers::PASSWORD }
    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(response.body).to include("Seu acesso ao Maney foi encerrado.")
  end

  it "is reversible" do
    delete person_access_path(irma)

    post person_access_path(irma)

    expect(irma.reload).not_to be_access_revoked
  end

  # The story's edge case: revoked while signed in on a phone. This drives the
  # filter directly (bypassing the controller) to cover it in isolation.
  it "returns someone revoked mid-session to the sign-in screen on their next action" do
    sign_out_request
    sign_in(irma)
    authenticate_request
    as(irma) { create_setting!; create_reserved_categories! }
    irma.update!(access_revoked_at: Time.current)

    get root_path

    expect(response).to redirect_to(new_session_path)
    expect(irma.sessions.count).to eq(0)
  end

  # The real path: Rafael revokes through the controller while Irma is signed
  # in elsewhere with an actual cookie-backed session. Her next request must
  # still show the alert — `AccessesController#destroy` must not pre-empt
  # `require_active_account` by destroying her session itself. The auth cookie
  # is swapped between the two real, cookie-backed logins to simulate two
  # different devices in one request-spec example — swapped by hand, not via
  # `sign_out_request`, which would hit the real sign-out endpoint and destroy
  # whichever session is active, defeating the very session this test needs to
  # survive until the final request.
  it "shows the alert on the revoked person's own next request, not only on their next sign-in" do
    admin = current_user

    sign_out_request
    sign_in(irma)
    authenticate_request
    irma_cookie = cookies["session_id"]
    as(irma) { create_setting!; create_reserved_categories! }

    cookies.delete("session_id")
    sign_in(admin)
    authenticate_request
    delete person_access_path(irma)
    expect(irma.reload).to be_access_revoked

    cookies["session_id"] = irma_cookie
    get root_path

    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(response.body).to include("Seu acesso ao Maney foi encerrado.")
    expect(irma.sessions.count).to eq(0)
  end

  it "refuses to revoke Rafael himself" do
    delete person_access_path(current_user)

    expect(current_user.reload).not_to be_access_revoked
    follow_redirect!
    expect(response.body).to include("Você é a única pessoa que pode convidar")
  end

  it "is unreachable for someone who is not Rafael" do
    other = create_user!(email_address: "outra@example.com")
    sign_out_request
    sign_in(other)
    authenticate_request
    as(other) { create_setting!; create_reserved_categories! }

    delete person_access_path(irma)

    expect(irma.reload).not_to be_access_revoked
  end
end
