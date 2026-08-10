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
    expect {
      post passwords_path, params: { email_address: current_user.email_address }
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

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
end
