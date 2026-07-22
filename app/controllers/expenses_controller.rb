class ExpensesController < ApplicationController
  def index
    @expenses = Budgeting::MonthEntries.expenses(month: current_month)
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
    # Precisa ser lido antes de `update`: se for uma parcela, a série inteira
    # é destruída e regenerada, e este número é a única forma de reencontrar
    # depois "a mesma parcela" que o usuário abriu (ver `month_of`).
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

  def source_for(expense) = expense.installment? ? expense.installment_purchase : expense

  # Para um gasto avulso, `record.date` já é a data certa: `ExpenseEntry#update`
  # reatribui e persiste o mesmo objeto, então `record` reflete o valor
  # recém-salvo. Para uma compra parcelada, `record.date` é a data da COMPRA —
  # ela só coincide com a competência da parcela editada quando essa parcela é
  # a de número `first_installment`; nos outros casos redirecionaria para um
  # mês que pode não conter parcela nenhuma da série (brief task-6, ponto 5).
  # Em vez disso, relocaliza a parcela original (pelo número, na série já
  # regenerada) e usa a competência dela de verdade. Se a edição encolheu a
  # série e essa parcela não existe mais, cai na primeira parcela restante —
  # o mesmo mês que o comportamento ingênuo já dava quando a parcela editada
  # era a âncora.
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
