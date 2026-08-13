require "rails_helper"

RSpec.describe User do
  include ActiveSupport::Testing::TimeHelpers

  it "is neither revoked nor deleted when it is just a person" do
    expect(current_user).not_to be_access_revoked
    expect(current_user).not_to be_deleted
  end

  it "is restorable inside the grace period and due for purging outside it" do
    current_user.update!(deleted_at: Time.current)
    expect(current_user).to be_restorable
    expect(current_user).not_to be_purge_due

    current_user.update!(deleted_at: User::DELETION_GRACE.ago - 1.minute)
    expect(current_user).not_to be_restorable
    expect(current_user).to be_purge_due
  end

  it "counts the days left before erasure" do
    current_user.update!(deleted_at: Time.current)

    expect(current_user.days_until_erasure).to eq(30)
  end

  it "lists only accounts past the grace period as purgeable" do
    inside = create_user!(email_address: "dentro@example.com")
    inside.update!(deleted_at: 29.days.ago)
    outside = create_user!(email_address: "fora@example.com")
    outside.update!(deleted_at: 31.days.ago)

    expect(User.purgeable).to contain_exactly(outside)
  end

  # The consent rule lives where the row is born, not in the view: without the
  # box ticked there is no INSERT at all.
  it "refuses to be created in the signup context without consent" do
    user = User.new(email_address: "irma@example.com", password: "segredo-de-teste",
                    password_confirmation: "segredo-de-teste")

    expect(user.save(context: :signup)).to be(false)
    expect(user.errors[:consent]).to be_present
  end

  it "is created in the signup context once consent is ticked" do
    user = User.new(email_address: "irma@example.com", password: "segredo-de-teste",
                    password_confirmation: "segredo-de-teste", consent: "1")

    expect(user.save(context: :signup)).to be(true)
  end
end
