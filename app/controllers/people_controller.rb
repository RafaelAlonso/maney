class PeopleController < ApplicationController
  # See InvitationsController for why this is `skip` + reinsert rather than
  # `skip_before_action :require_setup` alone or `prepend_before_action`.
  skip_before_action :require_setup
  before_action :require_admin
  before_action :require_setup

  # Statuses and email addresses only. This screen never touches an owned model,
  # which is what keeps W1's isolation intact while Rafael administers the group.
  def index
    @invitations = Invitation.pending.order(created_at: :desc)
    @people = User.order(:email_address)
  end

  # AC 16: an account Rafael deletes takes the same 30-day path, with the same
  # restore window, as one deleted by its owner.
  def destroy
    person = User.find(params[:id])

    if person == Current.user
      return redirect_to people_path,
                         alert: "Você é a única pessoa que pode convidar — sua conta não pode ser encerrada nem excluída."
    end

    person.delete_account!
    redirect_to people_path, notice: "Conta excluída — restaurável por 30 dias."
  end
end
