require "rails_helper"

RSpec.describe "Invitations", type: :request do
  before { create_setting!; create_reserved_categories! }

  # AC 1
  it "sends an invitation and shows the person as pending" do
    expect {
      post invitations_path, params: { invitation: { email_address: "irma@example.com" } }
    }.to change(Invitation, :count).by(1)

    perform_enqueued_jobs
    follow_redirect!
    expect(response.body).to include("irma@example.com")
    expect(response.body).to include("pendente")
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "irma@example.com" ])
  end

  it "records who sent it" do
    post invitations_path, params: { invitation: { email_address: "irma@example.com" } }

    expect(Invitation.last.invited_by).to eq(current_user)
  end

  # AC 7
  it "kills the link when Rafael cancels" do
    invitation, token = Invitation.issue(email_address: "irma@example.com", invited_by: current_user)

    delete invitation_path(invitation)

    expect(invitation.reload).not_to be_pending
    get signup_path(token: token)
    expect(response.body).to include("Este convite não é mais válido.")
  end

  # The brainstorming decision: a resend supersedes.
  it "kills the previously mailed link on resend" do
    invitation, first_token = Invitation.issue(email_address: "irma@example.com", invited_by: current_user)

    post resend_invitation_path(invitation)

    get signup_path(token: first_token)
    expect(response.body).to include("Este convite não é mais válido.")
    expect(Invitation.count).to eq(1)
  end

  it "refuses an address that already has an account" do
    create_user!(email_address: "irma@example.com")

    expect {
      post invitations_path, params: { invitation: { email_address: "irma@example.com" } }
    }.not_to change(Invitation, :count)

    follow_redirect!
    expect(response.body).to include("Essa pessoa já faz parte do grupo.")
  end

  # Edge case from the story: two invitations to the same address.
  it "lets a second invitation supersede the first" do
    _first, first_token = Invitation.issue(email_address: "irma@example.com", invited_by: current_user)

    post invitations_path, params: { invitation: { email_address: "irma@example.com" } }

    expect(Invitation.pending.count).to eq(1)
    get signup_path(token: first_token)
    expect(response.body).to include("Este convite não é mais válido.")
  end

  # AC 8: not a 403 — a 403 is a way of existing.
  it "hides every invitation route from someone who is not Rafael" do
    invitation, _token = Invitation.issue(email_address: "outra@example.com", invited_by: current_user)

    sign_out_request
    sign_in(create_user!(email_address: "irma@example.com"))
    authenticate_request

    post invitations_path, params: { invitation: { email_address: "outra2@example.com" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("Este registro não existe mais.")
    expect(Invitation.count).to eq(1)

    delete invitation_path(invitation)
    expect(response).to redirect_to(root_path)
    expect(invitation.reload).to be_pending

    post resend_invitation_path(invitation)
    expect(response).to redirect_to(root_path)
  end

  # Guards the fix for the ordering bug this task's review caught: `require_admin`
  # must run ahead of `require_setup` (so a non-admin is refused regardless of
  # their own setup state — the assertion above), but not ahead of
  # `require_authentication` — a signed-out visitor belongs at the sign-in
  # screen, not blocked here as if the route didn't exist.
  it "sends a signed-out visitor to the sign-in screen rather than treating them as a non-admin" do
    sign_out_request

    post invitations_path, params: { invitation: { email_address: "outra@example.com" } }

    expect(response).to redirect_to(new_session_path)
  end

  # And `require_setup` must still gate Rafael himself: `require_admin` runs
  # first so a non-admin's refusal never depends on the admin's own setup
  # state, but that reordering must not let an admin who hasn't finished
  # `/setup` reach this screen either.
  it "still sends an admin who has not completed setup to /setup" do
    sign_out_request
    sign_in(create_user!(email_address: "novo-admin@example.com", admin: true))
    authenticate_request

    post invitations_path, params: { invitation: { email_address: "outra@example.com" } }

    expect(response).to redirect_to(setup_path)
  end
end
