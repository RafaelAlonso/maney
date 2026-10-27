class AccountsController < ApplicationController
  before_action :set_account, only: %i[show edit update destroy]

  def index
    @accounts = Account.ordered
    @balances = Budgeting::AccountBalances.new(month: current_month)
  end

  # The account's month, the way the bank app shows it: what it opened with,
  # each movement with the balance after it, and what it closed with.
  def show
    @balances = Budgeting::AccountBalances.new(month: current_month)
    @movements = @balances.movements(@account)
  end

  def new
    @opening = AccountOpening.new(source_account_id: Account.primary.id)
  end

  def create
    @opening = AccountOpening.new(opening_params)
    if @opening.save
      redirect_to account_path(@opening.account), notice: "Conta aberta."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @account.update(params.require(:account).permit(:name))
      redirect_to account_path(@account), notice: "Conta atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Same rule as cards: an account with history is archived, not deleted.
  def destroy
    if @account.destroy
      redirect_to accounts_path, notice: "Conta excluída."
    elsif @account.reserved?
      redirect_to accounts_path, alert: "Esta conta não pode ser excluída."
    else
      redirect_to accounts_path, alert: "Conta com lançamentos não pode ser excluída — arquive-a."
    end
  end

  private

  def set_account = @account = Account.find(params[:id])

  def opening_params = params.require(:account_opening).permit(:name, :amount, :source_account_id)
end
