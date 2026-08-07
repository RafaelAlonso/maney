class SignupsController < ApplicationController
  # Opened by someone with no account and no Setting: both of the app's usual
  # gates have to stand aside.
  allow_unauthenticated_access
  skip_before_action :require_setup

  before_action :load_invitation

  def new
    @user = User.new
  end

  # The account, the consent record and the invitation's acceptance are one
  # transaction. Half of this is worse than none: an account whose consent was
  # never recorded has no legal basis to exist, and an invitation marked used
  # with no account behind it locks the person out of a group they were invited
  # to.
  def create
    @user = User.new(email_address: @invitation.email_address,
                     password: user_params[:password],
                     password_confirmation: user_params[:password_confirmation],
                     consent: user_params[:consent],
                     consented_at: Time.current,
                     consent_policy_version: PrivacyPolicy::VERSION)

    created = ActiveRecord::Base.transaction do
      next false unless @user.save(context: :signup)

      @invitation.update!(accepted_at: Time.current)
      true
    end

    if created
      start_new_session_for @user
      redirect_to setup_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params = params.require(:user).permit(:password, :password_confirmation, :consent)

  def load_invitation
    @invitation = Invitation.find_by_token(params[:token])
    return if @invitation&.redeemable?

    # Two messages, both of which say nothing about whose invitation it was.
    # "Expired" is separated out because it is the one case where asking Rafael
    # for a new link is the obvious next move.
    @message = if @invitation&.pending? && @invitation.expired?
      "Este convite expirou."
    else
      "Este convite não é mais válido."
    end

    # The import map's pinned package names ("@hotwired/...") would otherwise
    # put an "@" in this response, and this screen must reveal nothing about
    # whose invitation it was.
    @omit_importmap_tags = true
    render :invalid, status: :gone
  end
end
