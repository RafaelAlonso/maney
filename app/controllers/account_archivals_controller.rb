# Archiving, like CardArchivalsController: an archived account leaves the
# pickers for new entries and keeps its history and its balance in the total.
# The reserved Conta principal and Carteira can't be archived.
class AccountArchivalsController < ApplicationController
  before_action :set_account

  def create
    @account.archive!
    redirect_to accounts_path, notice: "Conta arquivada."
  rescue ActiveRecord::RecordInvalid
    redirect_to accounts_path, alert: "#{@account.name} não pode ser arquivada."
  end

  def destroy
    @account.reactivate!
    redirect_to accounts_path, notice: "Conta reativada."
  end

  private

  def set_account = @account = Account.find(params[:account_id])
end
