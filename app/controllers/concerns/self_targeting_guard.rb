# Neither revoking access nor deleting an account may target the caller's own
# record: Rafael is the sole inviter, so locking himself out (or deleting
# himself) would leave nobody able to invite. Shared by
# `People::AccessesController` (which keys on `params[:person_id]` via a
# `before_action`) and `PeopleController#destroy` (which keys on
# `params[:id]` and checks inline) — different shapes, same guard, so this
# takes the person rather than looking one up itself.
module SelfTargetingGuard
  extend ActiveSupport::Concern

  private

  ALERT = "Você é a única pessoa que pode convidar — sua conta não pode ser encerrada nem excluída.".freeze

  # Returns true (having already redirected) when `person` is the caller —
  # callers either wire this as a `before_action` wrapper or check the
  # return value inline, whichever fits their action.
  def refuse_self(person)
    return false unless person == Current.user

    redirect_to people_path, alert: ALERT
    true
  end

  # Same rule as `refuse_self`, but for actions with no separate "person"
  # argument to compare against — the caller *is* the target by construction
  # (`AccountDeletionsController#create` is always Current.user deleting
  # Current.user), so what disqualifies the action is being the sole
  # inviter, not an identity comparison. Non-admins are unaffected: deleting
  # your own account stays offered to everyone but the one person whose
  # departure would leave nobody able to invite.
  def refuse_admin_self_deletion
    return false unless Current.user.admin?

    redirect_to people_path, alert: ALERT
    true
  end
end
