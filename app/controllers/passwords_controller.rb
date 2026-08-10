class PasswordsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :require_active_account
  skip_before_action :require_setup
  before_action :load_user, only: %i[edit update]

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_password_path, alert: "Tente novamente em alguns minutos." }

  def new
  end

  # The branch is invisible from outside: the same redirect, the same message,
  # the same status, whether or not that address has an account. Anything else
  # turns this form into a way of asking who is in the group.
  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    PasswordsMailer.reset(user).deliver_later if user

    redirect_to new_session_path,
                notice: "Se esse email tiver uma conta, enviamos um link para redefinir a senha."
  end

  def edit
  end

  def update
    if @user.update(params.require(:user).permit(:password, :password_confirmation))
      redirect_to new_session_path, notice: "Senha alterada — pode entrar."
    else
      redirect_to edit_password_path(params[:token]), alert: @user.errors.full_messages.to_sentence
    end
  end

  private

  def load_user
    @user = User.find_by_token_for(:password_reset, params[:token])
    redirect_to new_password_path, alert: "Peça um novo link." unless @user
  end
end
