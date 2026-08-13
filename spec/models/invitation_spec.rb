require "rails_helper"

RSpec.describe Invitation do
  # This codebase includes the time helpers per spec file rather than globally
  # (see spec/models/card_spec.rb) — follow that.
  include ActiveSupport::Testing::TimeHelpers

  let(:rafael) { current_user }

  it "returns the token once and stores only its digest" do
    invitation, token = Invitation.issue(email_address: "irma@example.com", invited_by: rafael)

    expect(token).to be_present
    expect(invitation.token_digest).not_to eq(token)
    expect(Invitation.find_by_token(token)).to eq(invitation)
  end

  it "normalizes the address the same way a User does" do
    invitation, _token = Invitation.issue(email_address: "  Irma@Example.COM ", invited_by: rafael)

    expect(invitation.email_address).to eq("irma@example.com")
  end

  it "is redeemable while pending and unexpired" do
    invitation, _token = Invitation.issue(email_address: "irma@example.com", invited_by: rafael)

    expect(invitation).to be_redeemable
  end

  it "stops being redeemable after seven days" do
    invitation, _token = Invitation.issue(email_address: "irma@example.com", invited_by: rafael)

    travel_to(Invitation::EXPIRY.from_now + 1.minute) do
      expect(invitation).to be_expired
      expect(invitation).not_to be_redeemable
    end
  end

  it "stops being redeemable once cancelled" do
    invitation, _token = Invitation.issue(email_address: "irma@example.com", invited_by: rafael)

    invitation.cancel!

    expect(invitation).not_to be_pending
    expect(invitation).not_to be_redeemable
  end

  # The decision from brainstorming: a resend supersedes, it does not duplicate.
  # There is never more than one live link per address.
  it "kills the previously mailed link when reissued" do
    invitation, first_token = Invitation.issue(email_address: "irma@example.com", invited_by: rafael)

    second_token = invitation.reissue!

    expect(second_token).not_to eq(first_token)
    expect(Invitation.find_by_token(first_token)).to be_nil
    expect(Invitation.find_by_token(second_token)).to eq(invitation)
  end

  it "gives a reissued invitation a fresh seven days and a fresh delivery state" do
    invitation, _token = Invitation.issue(email_address: "irma@example.com", invited_by: rafael)
    invitation.update!(delivery_state: "failed", expires_at: 1.hour.from_now)

    invitation.reissue!

    expect(invitation.delivery_state).to eq("sending")
    expect(invitation.expires_at).to be > 6.days.from_now
  end

  it "records who opened the door" do
    invitation, _token = Invitation.issue(email_address: "irma@example.com", invited_by: rafael)

    expect(invitation.invited_by).to eq(rafael)
  end

  it "finds nothing for a blank or unknown token" do
    expect(Invitation.find_by_token(nil)).to be_nil
    expect(Invitation.find_by_token("")).to be_nil
    expect(Invitation.find_by_token("nao-existe")).to be_nil
  end
end
