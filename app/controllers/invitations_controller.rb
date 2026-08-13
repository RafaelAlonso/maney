class InvitationsController < ApplicationController
  # `require_admin` must run before `require_setup` — a non-admin's refusal
  # (AC 8) must not depend on whether they have completed their own setup —
  # but `require_authentication` (declared first, via `include Authentication`
  # on ApplicationController) must still run before either: a signed-out
  # visitor belongs at the sign-in screen, not blocked here. Verified with
  # `prepend_before_action :require_admin`: it also jumps ahead of
  # `require_authentication`, sending a signed-out visitor to `root_path`
  # instead of `new_session_path` — that would have been a regression, so we
  # skip and reinsert `require_setup` at the right spot instead.
  skip_before_action :require_setup
  before_action :require_admin
  before_action :require_setup

  def create
    email_address = params.require(:invitation)[:email_address].to_s.strip.downcase

    if User.exists?(email_address:)
      return redirect_to people_path, alert: "Essa pessoa já faz parte do grupo."
    end

    # One live link per address, always. A second invitation supersedes the
    # first rather than racing it.
    Invitation.pending.where(email_address:).find_each(&:cancel!)

    invitation, token = Invitation.issue(email_address:, invited_by: Current.user)
    Invitations::DeliveryJob.perform_later(invitation, token)

    redirect_to people_path, notice: "Convite enviado para #{email_address}."
  end

  def destroy
    invitation.cancel!
    redirect_to people_path, notice: "Convite cancelado."
  end

  def resend
    Invitations::DeliveryJob.perform_later(invitation, invitation.reissue!)
    redirect_to people_path, notice: "Convite reenviado — o link anterior deixou de valer."
  end

  private

  def invitation = @invitation ||= Invitation.find(params[:id])
end
