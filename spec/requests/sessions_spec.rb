require "rails_helper"

RSpec.describe "Sessions", type: :request do
  before { create_setting!; create_reserved_categories! }

  it "sends a signed-out visitor to the sign-in screen (AC 1)" do
    sign_out_request

    get root_path

    expect(response).to redirect_to(new_session_path)
  end

  it "lands on the month view after signing in (AC 2)" do
    sign_out_request

    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }

    expect(response).to redirect_to(root_url)
    follow_redirect!
    expect(response.body).to include("saldo atual")
  end

  it "issues a cookie that outlives the browser session (AC 3)" do
    sign_out_request

    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }

    set_cookie = Array(response.headers["set-cookie"]).join("\n")
    expect(set_cookie).to include("session_id=")
    # `cookies.signed.permanent` — an Expires ~20 years out. A cookie with no
    # Expires would die when the phone's browser closes, which is what AC 3
    # forbids, so the absence of this attribute is the actual regression.
    expect(set_cookie).to match(/expires=/i)
    expect(set_cookie).not_to match(/max-age=0/i)
  end

  it "requires signing in again after signing out (AC 4)" do
    delete session_path
    expect(response).to redirect_to(new_session_path)

    get root_path

    expect(response).to redirect_to(new_session_path)
  end

  it "does not say whether it was the email or the password (AC 9)" do
    sign_out_request

    post session_path, params: { email_address: current_user.email_address, password: "errada" }
    expect(flash[:alert]).to eq("Email ou senha inválidos.")

    post session_path, params: { email_address: "ninguem@example.com", password: "errada" }
    expect(flash[:alert]).to eq("Email ou senha inválidos.")
  end

  it "destroys only the signing-out device's session" do
    other_device = Session.create!(user: current_user)

    delete session_path

    expect(Session.exists?(other_device.id)).to be(true)
  end
end
