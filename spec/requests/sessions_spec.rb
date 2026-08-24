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

  # Finding 2: `require_active_account` sends every request from a
  # deleted-but-restorable person to the restore screen, `destroy` included —
  # that pinned someone who signed back in to reconsider on that screen with
  # no way out short of clearing cookies.
  it "lets a deleted-but-restorable person sign out from the restore screen" do
    sign_in_as_member!
    post account_deletion_path

    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }
    expect(response).to redirect_to(new_restoration_path)

    delete session_path
    expect(response).to redirect_to(new_session_path)

    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "offers a sign-out control on the restore screen itself" do
    sign_in_as_member!
    post account_deletion_path
    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }

    get new_restoration_path

    expect(response.body).to include(session_path)
  end

  it "shows no navigation for a deleted-but-restorable person" do
    sign_in_as_member!
    post account_deletion_path
    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }

    get new_restoration_path

    expect(response.body).not_to include("Categorias")
  end

  it "shows no navigation and no entry button while signed out" do
    sign_out_request

    get new_session_path

    expect(response.body).to include("Entrar")
    expect(response.body).not_to include("Categorias")
    expect(response.body).not_to include("Lançar")
  end

  it "shows the brand lockup on the signed-out sign-in screen" do
    sign_out_request

    get new_session_path

    # The brand lockup is now inlined SVG: the coin mark (its own viewBox) and
    # the wordmark (labelled "maney").
    expect(response.body).to include('viewBox="0 0 512 512"')
    expect(response.body).to include('aria-label="maney"')
  end

  it "shows no brand lockup once the app nav is present" do
    get root_path

    # The auth-only coin mark (its own viewBox) must not appear on app-nav
    # screens; the in-nav lockup is the wordmark, not the coin mark.
    expect(response.body).not_to include('viewBox="0 0 512 512"')
    expect(response.body).to include("Categorias")
  end

  it "renders the sign-in form in the design system (AC 1)" do
    sign_out_request

    get new_session_path

    expect(response.body).to include("btn btn-primary")
    expect(response.body).to include("field-input")
  end

  it "renders the restoration screen in the design system (AC 5)" do
    sign_in_as_member!
    post account_deletion_path
    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }

    get new_restoration_path

    expect(response.body).to include("btn btn-primary")
    expect(response.body).to include("btn btn-secondary")
  end
end
