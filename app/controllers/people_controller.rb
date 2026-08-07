class PeopleController < ApplicationController
  # See InvitationsController: `require_admin` must fire even for a signed-in
  # non-admin who has not completed `/setup`, which `require_setup` — declared
  # on ApplicationController and so ordered first — would otherwise intercept.
  skip_before_action :require_setup
  before_action :require_admin

  # Statuses and email addresses only. This screen never touches an owned model,
  # which is what keeps W1's isolation intact while Rafael administers the group.
  def index
    @invitations = Invitation.pending.order(created_at: :desc)
    @people = User.order(:email_address)
  end
end
