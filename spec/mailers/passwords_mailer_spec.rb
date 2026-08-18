require "rails_helper"

RSpec.describe PasswordsMailer, type: :mailer do
  it "renders a branded, inline-styled, imageless HTML part" do
    mail = PasswordsMailer.reset(current_user)
    html = mail.html_part.body.to_s

    expect(html).to include("maney")
    expect(html).to include("#059669")
    expect(html).to match(/<a[^>]+style=/)
    expect(html).not_to include("<img")
  end

  it "keeps the plain-text part and the reset link intact" do
    mail = PasswordsMailer.reset(current_user)
    text = mail.text_part.body.to_s

    expect(text).to include("Se não foi você, ignore este email.")
    expect(text).to match(%r{/passwords/[^/]+/edit})
  end
end
