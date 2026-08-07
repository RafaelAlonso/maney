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
    pending "SignupsController arrives in Task 5"

    invitation, token = Invitation.issue(email_address: "irma@example.com", invited_by: current_user)

    delete invitation_path(invitation)

    expect(invitation.reload).not_to be_pending
    get signup_path(token: token)
    expect(response.body).to include("Este convite não é mais válido.")
  end

  # The brainstorming decision: a resend supersedes.
  it "kills the previously mailed link on resend" do
    pending "SignupsController arrives in Task 5"

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
    pending "SignupsController arrives in Task 5"

    _first, first_token = Invitation.issue(email_address: "irma@example.com", invited_by: current_user)

    post invitations_path, params: { invitation: { email_address: "irma@example.com" } }

    expect(Invitation.pending.count).to eq(1)
    get signup_path(token: first_token)
    expect(response.body).to include("Este convite não é mais válido.")
  end

  # AC 8: not a 403 — a 403 is a way of existing.
  it "hides every invitation route from someone who is not Rafael" do
    sign_out_request
    sign_in(create_user!(email_address: "irma@example.com"))
    authenticate_request

    post invitations_path, params: { invitation: { email_address: "outra@example.com" } }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to eq("Este registro não existe mais.")
    expect(Invitation.count).to eq(0)
  end
end
