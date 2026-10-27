# Paying a card bill. New payments are created against a statement (nested
# under it, so the link is set at birth); an existing one is edited and deleted
# on its own, because its statement may no longer resolve — all its purchases
# deleted — and the payment, real money that left an account, must stay
# reachable.
class StatementPaymentsController < ApplicationController
  before_action :set_statement, only: %i[new create]
  before_action :set_payment, only: %i[edit update destroy]

  def new
    remaining = Budgeting::StatementPayments.new.remaining_cents(@row.statement, @row.total_cents)
    @entry = StatementPaymentEntry.new(account_id: Account.last_used_id(Expense.statement_payments),
                                       amount: BrlMoney.format(remaining), date: Date.current)
  end

  def create
    @entry = StatementPaymentEntry.new(entry_params)
    if @entry.save(card: @card, statement: @row.statement)
      redirect_to after_payment_path(@entry.record), notice: "Pagamento lançado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @entry = StatementPaymentEntry.from(@payment)
  end

  def update
    @entry = StatementPaymentEntry.new(entry_params)
    if @entry.update(@payment)
      redirect_to after_payment_path(@payment), notice: "Pagamento atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @payment.destroy
    redirect_to after_payment_path(@payment), notice: "Pagamento excluído."
  end

  private

  # A malformed id and one that no longer resolves both mean the statement
  # isn't there to pay.
  def set_statement
    @card = Card.find(params[:card_id])
    @row = Budgeting::CardStatements.new(card: @card).find(Date.iso8601(params[:statement_id]))
    redirect_to card_statements_path(@card), alert: "Fatura não encontrada." if @row.nil?
  rescue Date::Error
    redirect_to card_statements_path(@card), alert: "Fatura não encontrada."
  end

  # Only linked payments have this form; an unlinked one (entered before
  # "pagar" existed) is an ordinary expense edit.
  def set_payment
    @payment = Expense.where.not(statement_card_id: nil).find(params[:id])
  end

  def entry_params = params.require(:statement_payment_entry).permit(:account_id, :amount, :date)

  # Back where the person started: Início (the statement's due month) when
  # "pagar" was tapped there, else the statement — or, when the statement no
  # longer resolves, the paying account's month.
  def after_payment_path(payment)
    statement = Budgeting::StatementPayments.new.statement_for(payment)
    if params[:from] == "home" && statement
      root_path(month: statement.effective_due.strftime("%Y-%m"))
    elsif statement
      card_statement_path(statement.card, statement)
    else
      account_path(payment.account, month: payment.date.strftime("%Y-%m"))
    end
  end
end
