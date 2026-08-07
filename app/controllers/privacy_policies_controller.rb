class PrivacyPoliciesController < ApplicationController
  # Read by people who have no account yet — the invitation screen shows this
  # same text — and by people whose app has never been set up.
  allow_unauthenticated_access
  skip_before_action :require_setup

  def show
  end
end
