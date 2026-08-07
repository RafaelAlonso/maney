module People
  class AccessesController < ApplicationController
    # See InvitationsController for why this is `skip` + reinsert rather than
    # `skip_before_action :require_setup` alone or `prepend_before_action`.
    skip_before_action :require_setup
    before_action :require_admin
    before_action :require_setup
    before_action :refuse_self

    def create
      person.update!(access_revoked_at: nil)
      redirect_to people_path, notice: "Acesso restaurado."
    end

    def destroy
      # Revoking erases nothing. Every row the person owns stays exactly where
      # it is, which is what makes this reversible.
      person.update!(access_revoked_at: Time.current)
      person.sessions.destroy_all
      redirect_to people_path, notice: "Acesso encerrado."
    end

    private

    def person = @person ||= User.find(params[:person_id])

    def refuse_self
      return unless person == Current.user

      redirect_to people_path,
                  alert: "Você é a única pessoa que pode convidar — sua conta não pode ser encerrada nem excluída."
    end
  end
end
