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
    user = User.authenticate_by(params.permit(:email_address, :password))

    # One message for a wrong email and for a wrong password alike: telling
    # them apart tells a stranger which addresses have an account here.
    return redirect_to new_session_path, alert: "Email ou senha inválidos." if user.nil?

    # Only shown *after* correct credentials, so it reveals nothing to a
    # stranger — and it keeps a family member out of a password-recovery loop
    # that could never have helped them.
    if user.access_revoked?
      return redirect_to new_session_path, alert: "Seu acesso ao Maney foi encerrado."
    end

    # Past the grace period the row may still exist — the purge runs nightly —
    # but the app must already answer as though it does not.
    if user.purge_due?
      return redirect_to new_session_path, alert: "Email ou senha inválidos."
    end

    start_new_session_for user

    # A deleted-but-restorable person signs in normally: the session exists so
    # they can reach `RestorationsController`, which is the one screen that
    # doesn't require `require_active_account`. Sending them to
    # `after_authentication_url` first would land them on a page that filter
    # then bounces anyway — this goes straight there.
    return redirect_to new_restoration_path if user.deleted?

    redirect_to after_authentication_url
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
