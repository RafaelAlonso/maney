class AccountDeletionsController < ApplicationController
  include SelfTargetingGuard

  # `new` is a real screen rather than a browser dialog: the copy has to name
  # both the 30 days and the permanence, which is more than a confirm box can
  # carry.
  def new
  end

  def create
    # See SelfTargetingGuard#refuse_admin_self_deletion: PeopleController
    # already refuses this same operation for the admin ("the account that
    # invites can't be deleted"); without this check, this screen offered a
    # second, contradicting path to the same outcome.
    return if refuse_admin_self_deletion

    Current.user.delete_account!
    # Not `terminate_session`: `delete_account!` already destroyed the
    # session row itself (via `sessions.destroy_all`), so there is nothing
    # left for `Current.session.destroy` to act on — only the browser's
    # cookie still needs clearing.
    cookies.delete(:session_id)
    redirect_to new_session_path,
                notice: "Sua conta foi excluída. Você tem 30 dias para voltar atrás entrando de novo."
  end
end
