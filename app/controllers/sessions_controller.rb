class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  # Signing in must work before the app has been set up — an admin creates the
  # first person via `rails console` and signs in before ever touching /setup.
  # Without this, `require_setup` would redirect a fresh install's first sign-in
  # attempt to /setup, which itself requires authentication, deadlocking.
  skip_before_action :require_setup
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: "Tente novamente em alguns minutos." }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      # One message for a wrong email and for a wrong password alike: telling
      # them apart tells a stranger which addresses have an account here.
      redirect_to new_session_path, alert: "Email ou senha inválidos."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
