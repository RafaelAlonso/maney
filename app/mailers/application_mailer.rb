class ApplicationMailer < ActionMailer::Base
  # The verified Brevo sender. Configured rather than hard-coded because the
  # address that Brevo will accept differs between Rafael's machine and the
  # deployed instance.
  default from: ENV.fetch("MANEY_MAIL_FROM", "maney@example.com")
  layout "mailer"
end
