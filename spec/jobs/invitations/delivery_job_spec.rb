require "rails_helper"

RSpec.describe Invitations::DeliveryJob do
  let(:issued) { Invitation.issue(email_address: "irma@example.com", invited_by: current_user) }
  let(:invitation) { issued.first }
  let(:token) { issued.last }

  it "sends the invitation and marks it sent" do
    expect { described_class.perform_now(invitation, token) }
      .to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(invitation.reload.delivery_state).to eq("sent")
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "irma@example.com" ])
  end

  it "puts the live link in the email" do
    described_class.perform_now(invitation, token)

    expect(ActionMailer::Base.deliveries.last.body.encoded).to include(token)
  end

  # Rafael cannot see an exception raised inside a background job. The story
  # requires the failure to reach his list instead, so the job swallows the
  # error on purpose and records it on the row — that column is the whole
  # mechanism behind "não enviado" plus Reenviar.
  it "records a failed send instead of raising" do
    allow(InvitationMailer).to receive(:invite).and_raise(Net::SMTPAuthenticationError, "535 bad credentials")

    expect { described_class.perform_now(invitation, token) }.not_to raise_error

    expect(invitation.reload.delivery_state).to eq("failed")
  end
end
