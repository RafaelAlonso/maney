module People
  class AccessesController < ApplicationController
    include SelfTargetingGuard

    # See InvitationsController for why this is `skip` + reinsert rather than
    # `skip_before_action :require_setup` alone or `prepend_before_action`.
    skip_before_action :require_setup
    before_action :require_admin
    before_action :require_setup
    before_action :refuse_self_as_target

    def create
      person.update!(access_revoked_at: nil)
      redirect_to people_path, notice: "Acesso restaurado."
    end

    def destroy
      # Revoking erases nothing. Every row the person owns stays exactly where
      # it is, which is what makes this reversible.
      #
      # Deliberately does not touch the person's sessions: `require_active_account`
      # is what closes those out, on the revoked person's own next request. If
      # this destroyed her session row itself, her cookie would point at nothing,
      # `require_authentication` would catch it first and bounce her to sign-in
      # with no alert at all — the "Seu acesso ao Maney foi encerrado." message
      # would only ever appear on her next sign-in, not on her next action.
      person.update!(access_revoked_at: Time.current)
      redirect_to people_path, notice: "Acesso encerrado."
    end

    private

    def person = @person ||= User.find(params[:person_id])

    def refuse_self_as_target = refuse_self(person)
  end
end
