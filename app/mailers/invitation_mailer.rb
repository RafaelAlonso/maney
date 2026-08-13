class InvitationMailer < ApplicationMailer
  # The token is passed in rather than read off the invitation: only the digest
  # is stored, so this is the one moment the live link can be built.
  def invite(invitation, token)
    @url = signup_url(token: token)
    # 8bit transport, not the default quoted-printable: quoted-printable's
    # 76-column soft wrap would slice the token in the middle of the link
    # (it doesn't care about word boundaries), which is fine for a QP-aware
    # reader but breaks a plain substring check and is an unnecessary risk
    # for a one-time link. Modern SMTP (8BITMIME) carries UTF-8 as-is.
    mail(to: invitation.email_address, subject: "Seu convite para o Maney")
      .tap { |message| message.transport_encoding = "8bit" }
  end
end
