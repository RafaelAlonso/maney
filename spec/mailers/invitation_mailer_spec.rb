require "rails_helper"

RSpec.describe InvitationMailer, type: :mailer do
  it "renders a branded, inline-styled, imageless HTML part" do
    invitation, token = Invitation.issue(email_address: "irma@example.com", invited_by: current_user)

    mail = InvitationMailer.invite(invitation, token)
    html = mail.html_part.body.to_s

    expect(html).to include("maney")        # typographic wordmark
    expect(html).to include("#059669")      # mint brand color, inline
    expect(html).to match(/<a[^>]+style=/)  # inline-styled CTA button
    expect(html).not_to include("<img")     # no images, per the email decision
  end

  it "keeps the plain-text part and the live link intact" do
    invitation, token = Invitation.issue(email_address: "irma@example.com", invited_by: current_user)

    mail = InvitationMailer.invite(invitation, token)
    text = mail.text_part.body.to_s

    expect(text).to include(signup_url(token: token))
    expect(text).to include("Este convite vale por 7 dias.")
  end
end
