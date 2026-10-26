# Money moving between two of the person's own accounts (a saque is one, to the
# carteira). Reached from an account's page, and it returns there.
class TransfersController < ApplicationController
  before_action :set_transfer, only: %i[edit update destroy]

  def new
    @transfer = Transfer.new(date: default_entry_date,
                             from_account: Account.find_by(id: params[:from_account_id]) || Account.primary)
  end

  def create
    @transfer = Transfer.new
    if assign_and_save(@transfer)
      redirect_to origin_page(@transfer), notice: "Transferência lançada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if assign_and_save(@transfer)
      redirect_to origin_page(@transfer), notice: "Transferência atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @transfer.destroy
    redirect_to origin_page(@transfer), notice: "Transferência excluída."
  end

  private

  def set_transfer = @transfer = Transfer.find(params[:id])

  def origin_page(transfer) = account_path(transfer.from_account, month: transfer.date.strftime("%Y-%m"))

  # Same technique as IncomesController#assign_and_save: parse before touching
  # `amount_cents`, keep the typed text in `amount` so a 422 re-renders it, and
  # put the message on the field the form shows. Account ids go through the
  # default scope, so another person's id is simply not found.
  def assign_and_save(transfer)
    permitted = params.require(:transfer).permit(:from_account_id, :to_account_id, :amount, :date, :note)
    transfer.from_account = Account.find_by(id: permitted[:from_account_id].presence)
    transfer.to_account = Account.find_by(id: permitted[:to_account_id].presence)
    transfer.date = permitted[:date]
    transfer.note = permitted[:note].presence
    transfer.amount = permitted[:amount]
    cents = BrlMoney.parse(permitted[:amount])
    transfer.amount_cents = cents if cents
    if cents.nil?
      transfer.valid?
      transfer.errors.delete(:amount_cents)
      transfer.errors.add(:amount, "não é um valor válido")
      return false
    end
    return true if transfer.save
    remap_amount_cents_errors(transfer)
    false
  end

  def remap_amount_cents_errors(transfer)
    amount_errors = transfer.errors.where(:amount_cents).to_a
    return if amount_errors.empty?
    transfer.errors.delete(:amount_cents)
    amount_errors.each { |error| transfer.errors.import(error, attribute: :amount) }
  end
end
