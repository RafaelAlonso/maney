require "rails_helper"

RSpec.describe "Password recovery", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!; create_reserved_categories!; sign_out_request }

  # AC 12: the confirmation is identical either way. Compared byte for byte,
  # because a difference of one word is enough to turn this screen into a
  # test for whether an address has an account here.
  it "answers identically for an address with and without an account" do
    post passwords_path, params: { email_address: current_user.email_address }
    follow_redirect!
    known = response.body

    post passwords_path, params: { email_address: "ninguem@example.com" }
    follow_redirect!
    unknown = response.body

    expect(known).to eq(unknown)
  end

  it "emails a real account a link that sets a new password" do
    perform_enqueued_jobs do
      expect {
        post passwords_path, params: { email_address: current_user.email_address }
      }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    token = current_user.generate_token_for(:password_reset)
    put password_path(token), params: { user: { password: "nova-senha-longa",
                                                password_confirmation: "nova-senha-longa" } }

    expect(response).to redirect_to(new_session_path)
    post session_path, params: { email_address: current_user.email_address, password: "nova-senha-longa" }
    expect(response).to redirect_to(root_url)
  end

  it "sends nothing to an address without an account" do
    expect {
      post passwords_path, params: { email_address: "ninguem@example.com" }
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  # A revoked or deleted account is treated like an address with no account:
  # the row survives, but it is not one the app will help back in.
  it "sends nothing to an account whose access was revoked" do
    current_user.update!(access_revoked_at: Time.current)

    expect {
      post passwords_path, params: { email_address: current_user.email_address }
    }.not_to change { ActionMailer::Base.deliveries.size }
  end

  # A link mailed while the account was still active must not let the password
  # be changed once the account has since been deleted — the token is still
  # cryptographically valid (the salt is untouched), so only the active-account
  # check stands between it and a mutation of a row that is on its way out.
  it "refuses to complete a reset for an account deleted after the link was issued" do
    token = current_user.generate_token_for(:password_reset)
    current_user.update!(deleted_at: Time.current)

    get edit_password_path(token)
    expect(response).to redirect_to(new_password_path)

    put password_path(token), params: { user: { password: "nova-senha-longa",
                                                password_confirmation: "nova-senha-longa" } }
    expect(response).to redirect_to(new_password_path)
  end

  it "refuses an expired link" do
    token = current_user.generate_token_for(:password_reset)

    travel_to(16.minutes.from_now) do
      get edit_password_path(token)

      expect(response).to redirect_to(new_password_path)
      follow_redirect!
      expect(response.body).to include("Peça um novo link.")
    end
  end

  # The token is keyed on the password salt, so using it once burns it.
  it "refuses a link that has already been used" do
    token = current_user.generate_token_for(:password_reset)
    put password_path(token), params: { user: { password: "nova-senha-longa",
                                                password_confirmation: "nova-senha-longa" } }

    get edit_password_path(token)

    expect(response).to redirect_to(new_password_path)
  end

  it "is linked from the sign-in screen" do
    get new_session_path

    expect(response.body).to include(new_password_path)
  end

  it "shows a fully Portuguese message when the confirmation does not match" do
    token = current_user.generate_token_for(:password_reset)
    put password_path(token), params: { user: { password: "nova-senha-longa",
                                                password_confirmation: "outra-coisa" } }

    expect(response).to redirect_to(edit_password_path(token))
    follow_redirect!
    expect(response.body).to include("Confirmação de senha não corresponde a Senha")
  end
end
