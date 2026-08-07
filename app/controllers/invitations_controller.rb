class InvitationsController < ApplicationController
  # Administering the group is orthogonal to Rafael's own budget setup, and AC 8
  # needs `require_admin` to fire for a non-admin unconditionally — including
  # one who has not been through `/setup` yet, which `require_setup` (declared
  # on ApplicationController, and so ordered first) would otherwise intercept.
  skip_before_action :require_setup
  before_action :require_admin

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
