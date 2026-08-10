class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @url = edit_password_url(token: user.generate_token_for(:password_reset))
    mail to: user.email_address, subject: "Redefinir sua senha do Maney"
  end
end
