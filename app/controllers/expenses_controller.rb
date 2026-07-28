class ExpensesController < ApplicationController
  def index
    @expenses = Budgeting::MonthEntries.expenses(month: current_month)
    @statements = Budgeting::StatementSet.labels_for(@expenses)
  end

  def new
    @entry = ExpenseEntry.new(date: Date.current, payment_method: "debit")
  end

  def create
    @entry = ExpenseEntry.new(entry_params)
    if @entry.save
      redirect_to expenses_path(month: month_of(@entry.record)), notice: "Gasto lançado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @expense = Expense.find(params[:id])
    @entry = ExpenseEntry.from(source_for(@expense))
  end

  def update
    @expense = Expense.find(params[:id])
    # Must be read before `update`: if it's an installment, the whole series is
    # destroyed and regenerated, and this number is the only way to find again
    # afterward "the same installment" the user opened (see `month_of`).
    original_installment_number = @expense.installment_number
    @entry = ExpenseEntry.new(entry_params)
    if @entry.update(source_for(@expense))
      redirect_to expenses_path(month: month_of(@entry.record, original_installment_number)), notice: "Gasto atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    expense = Expense.find(params[:id])
    if expense.installment?
      expense.installment_purchase.destroy
      redirect_to expenses_path, notice: "Compra parcelada excluída por inteiro."
    else
      expense.destroy
      redirect_to expenses_path, notice: "Gasto excluído."
    end
  end

  private

  # Overrides `ApplicationController`'s generic handler: here, and only here, the
  # stale id has a concrete, explainable cause — editing an installment destroys
  # and regenerates the whole series, so an `/expenses/:id` link left open in
  # another tab can start pointing at an installment that no longer exists.
  # Outside this controller (e.g. `CardsController`) that explanation doesn't
  # apply and must not appear.
  def record_not_found
    redirect_to root_path,
                alert: "Este registro não existe mais — editar uma parcela recalcula a compra inteira " \
                       "e pode ter substituído os ids das parcelas."
  end

  def source_for(expense) = expense.installment? ? expense.installment_purchase : expense

  # For a standalone expense, `record.date` is already the right date:
  # `ExpenseEntry#update` reassigns and persists the same object, so `record`
  # reflects the just-saved value. For an installment purchase, `record.date` is
  # the PURCHASE's date — it only coincides with the edited installment's
  # competence when that installment is the one numbered `first_installment`; in
  # the other cases it would redirect to a month that may contain no installment
  # of the series at all (brief task-6, point 5). Instead, it relocates the
  # original installment (by number, in the already-regenerated series) and uses
  # its real competence. If the edit shrank the series and that installment no
  # longer exists, it falls back to the first remaining installment — the same
  # month the naive behavior already gave when the edited installment was the anchor.
  def month_of(record, original_installment_number = nil)
    return record.date&.strftime("%Y-%m") unless record.is_a?(InstallmentPurchase)
    expenses = record.expenses.order(:installment_number).to_a
    target = expenses.find { |e| e.installment_number == original_installment_number } || expenses.first
    return record.date&.strftime("%Y-%m") if target.nil?
    Budgeting::Competence.month_of(target).strftime("%Y-%m")
  end

  def entry_params
    params.require(:expense_entry)
          .permit(:name, :amount, :date, :category_id, :payment_method,
                  :card_id, :installment, :installments_count, :first_installment)
  end
end
