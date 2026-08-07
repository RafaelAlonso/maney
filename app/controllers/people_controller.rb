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
end
