require "rails_helper"

RSpec.describe "Account deletion", type: :request do
  before { create_setting!; create_reserved_categories! }

  # AC 13
  it "signs the person out at once and says what happens in 30 days" do
    sign_in_as_member!

    get new_account_deletion_path
    expect(response.body).to include("30 dias")
    expect(response.body).to include("definitiv")

    post account_deletion_path

    expect(current_user.reload).to be_deleted
    expect(current_user.sessions.count).to eq(0)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "erases nothing on the day it is asked for" do
    sign_in_as_member!
    Income.create!(name: "Salário", amount_cents: 100_00, date: Date.new(2026, 3, 5))

    post account_deletion_path

    expect(Income.unscoped.where(user_id: current_user.id).count).to eq(1)
  end

  # AC 14
  it "offers restoration inside the 30 days and nothing else" do
    sign_in_as_member!
    Income.create!(name: "Salário", amount_cents: 100_00, date: Date.new(2026, 3, 5))
    post account_deletion_path

    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }
    expect(response).to redirect_to(new_restoration_path)

    get root_path
    expect(response).to redirect_to(new_restoration_path)

    get new_restoration_path
    expect(response.body).to include("30")

    post restoration_path
    expect(current_user.reload).not_to be_deleted
    expect(Income.unscoped.where(user_id: current_user.id).count).to eq(1)

    get root_path
    expect(response).to have_http_status(:ok)
  end

  # AC 15, before the nightly purge has had a chance to run.
  it "behaves as though a past-30-days account is already gone" do
    current_user.update!(deleted_at: (User::DELETION_GRACE + 1.day).ago)
    sign_out_request

    post session_path, params: { email_address: current_user.email_address,
                                 password: AuthenticationHelpers::PASSWORD }

    expect(response).to redirect_to(new_session_path)
    follow_redirect!
    expect(response.body).to include("Email ou senha inválidos.")
  end

  # A person restoring on day 29 and deleting again gets a fresh window,
  # because the window is derived from deleted_at and nothing else.
  it "starts a fresh window on a second deletion" do
    current_user.update!(deleted_at: 29.days.ago)

    current_user.restore_account!
    current_user.delete_account!

    expect(current_user.days_until_erasure).to eq(30)
  end

  # AC 16
  it "puts an account Rafael deletes on the same path" do
    irma = create_user!(email_address: "irma@example.com")

    delete person_path(irma)

    expect(irma.reload).to be_deleted
    expect(irma).to be_restorable
  end

  it "refuses to let Rafael delete himself" do
    delete person_path(current_user)

    expect(current_user.reload).not_to be_deleted
  end

  # Finding 1 from the whole-branch review: PeopleController already refuses
  # this for the admin; this screen offered a second, contradicting path to
  # the same unrecoverable outcome (a group with nobody left who can invite).
  it "refuses to let the admin delete his own account directly" do
    post account_deletion_path

    expect(current_user.reload).not_to be_deleted
    expect(response).to redirect_to(people_path)
    follow_redirect!
    expect(response.body).to include("sua conta não pode ser encerrada nem excluída")
  end

  it "is offered to everyone, not only Rafael" do
    irma = create_user!(email_address: "irma@example.com")
    sign_out_request
    sign_in(irma)
    authenticate_request
    as(irma) { create_setting!; create_reserved_categories! }

    get edit_settings_path

    expect(response.body).to include(new_account_deletion_path)
  end
end
