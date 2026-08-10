class RestorationsController < ApplicationController
  # The one screen a deleted person can reach.
  skip_before_action :require_active_account
  skip_before_action :require_setup

  before_action :require_restorable

  def new
  end

  def create
    Current.user.restore_account!
    redirect_to root_path, notice: "Conta restaurada."
  end

  private

  def require_restorable
    redirect_to root_path unless Current.user&.restorable?
  end
end
