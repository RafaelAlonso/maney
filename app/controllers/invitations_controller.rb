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
  # Both actions only make sense while the invitation is still open. Resending
  # an accepted one would reissue a live token whose `redeemable?` is already
  # false — the recipient's fresh link would dead-end at the "gone" screen — and
  # cancelling an already-accepted invitation would stamp `cancelled_at` on a
  # door someone has already walked through. The UI never offers either, but the
  # routes accept a direct POST, so the guard lives here.
  before_action :require_pending_invitation, only: %i[resend destroy]

  def create
    email_address = params.require(:invitation)[:email_address].to_s.strip.downcase

    # A row still holds this address either way, and the unique index on
    # `users.email_address` (plus signup's lack of a model-level uniqueness
    # check) means letting a second account be created for it would blow up at
    # accept time — so we block regardless of the account's state. The message,
    # though, must be honest: "já faz parte do grupo" is a lie for someone whose
    # access was revoked or whose account is on its way out.
    if (existing = User.find_by(email_address:))
      message = if existing.active?
        "Essa pessoa já faz parte do grupo."
      else
        "Esse email está vinculado a uma conta encerrada e não pode receber um novo convite."
      end
      return redirect_to people_path, alert: message
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

  def require_pending_invitation
    return if invitation.pending?

    redirect_to people_path, alert: "Esse convite já não está pendente."
  end

  def invitation = @invitation ||= Invitation.find(params[:id])
end
