require "rails_helper"

RSpec.describe "Signups", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:rafael) { current_user }
  let(:issued) { Invitation.issue(email_address: "irma@example.com", invited_by: rafael) }
  let(:invitation) { issued.first }
  let(:token) { issued.last }

  def accept(params = {})
    post signup_path(token: token), params: {
      user: { password: "segredo-de-teste", password_confirmation: "segredo-de-teste", consent: "1" }.merge(params)
    }
  end

  # AC 2
  it "shows the policy and a consent checkbox" do
    get signup_path(token: token)

    expect(response.body).to include("O que coletamos")
    expect(response.body).to include("user[consent]")
  end

  # AC 2 again: the rule is enforced where the row is born, not in the view.
  it "creates no account when consent is not ticked" do
    invitation

    expect { accept(consent: "0") }.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("Consentimento")
    expect(invitation.reload).to be_pending
  end

  # AC 3
  it "creates the account, signs them in, and starts first-run setup" do
    invitation

    expect { accept }.to change(User, :count).by(1)

    expect(response).to redirect_to(setup_path)
    follow_redirect!
    expect(response.body).to include("Primeiro mês")
  end

  it "gives the new person an empty budget of their own" do
    invitation
    accept

    irma = User.find_by(email_address: "irma@example.com")
    as(irma) do
      expect(Setting.instance).to be_nil
      expect(Category.count).to eq(0)
      expect(Expense.count).to eq(0)
    end
  end

  # AC 4
  it "records who consented, when, and to which version" do
    invitation
    freeze_time do
      accept

      irma = User.find_by(email_address: "irma@example.com")
      expect(irma.consented_at).to eq(Time.current)
      expect(irma.consent_policy_version).to eq(PrivacyPolicy::VERSION)
    end
  end

  # AC 5
  it "refuses a link that has already been used" do
    invitation
    accept
    sign_out_request

    expect { get signup_path(token: token) }.not_to change(User, :count)
    expect(response.body).to include("Este convite não é mais válido.")
  end

  # AC 6
  it "refuses a link older than seven days" do
    invitation

    travel_to(Invitation::EXPIRY.from_now + 1.minute) do
      get signup_path(token: token)

      expect(response.body).to include("Este convite expirou.")
    end
  end

  it "says nothing about who an unknown link belonged to" do
    get signup_path(token: "nao-existe")

    expect(response.body).to include("Este convite não é mais válido.")
    expect(response.body).not_to include("@")
  end

  it "brands the invalid-invite screen without leaking the invitee" do
    get signup_path(token: "nao-existe")

    expect(response.body).to include("coin_m")
    expect(response.body).not_to include("@")
  end

  it "is reachable while signed out and before any setup exists" do
    invitation
    sign_out_request

    get signup_path(token: token)

    expect(response).to have_http_status(:ok)
  end

  it "renders the signup form in the design system (AC 2)" do
    get signup_path(token: token)

    expect(response.body).to include("btn btn-primary")
    expect(response.body).to include("field-input")
    expect(response.body).not_to include("bg-blue-600")
  end
end
