class PrivacyPoliciesController < ApplicationController
  # Read by people who have no account yet — the invitation screen shows this
  # same text — and by people whose app has never been set up.
  allow_unauthenticated_access
  # A public page: no account is required to read it, so the active-account gate
  # has nothing to check. Opt out explicitly instead of relying on the session
  # never being resumed here.
  skip_before_action :require_active_account
  skip_before_action :require_setup

  def show
  end
end
