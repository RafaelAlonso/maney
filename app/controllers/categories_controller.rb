class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]

  def index
    @categories = Category.order(:name)
    @budgets = Budget.where(month: current_month).index_by(&:category_id)
  end

  def show
    @expenses = Budgeting::MonthEntries.expenses(month: current_month, category: @category)
  end

  def new
    @category = Category.new
    @budget_amount = nil
  end

  def create
    @category = Category.new(name: category_params[:name])
    if save_category_and_budget
      redirect_to categories_path(month: month_param), notice: "Categoria criada."
    else
      @budget_amount = category_params[:budget_amount]
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @budget_amount = current_budget_amount
  end

  def update
    if save_category_and_budget(update: true)
      redirect_to categories_path(month: month_param), notice: "Categoria atualizada."
    else
      @budget_amount = category_params[:budget_amount]
      render :edit, status: :unprocessable_entity
    end
  end

  # Excluir move os gastos (e compras parceladas) para a padrão — o aviso
  # com a contagem fica no turbo_confirm da lista.
  def destroy
    if @category.reserved?
      redirect_to categories_path, alert: "Categoria reservada não pode ser excluída."
      return
    end
    default = Category.find_by!(role: "others")
    ActiveRecord::Base.transaction do
      @category.expenses.update_all(category_id: default.id)
      InstallmentPurchase.where(category: @category).update_all(category_id: default.id)
      @category.reload.destroy!
    end
    redirect_to categories_path, notice: "Categoria excluída; gastos movidos para #{default.name}."
  end

  private

  def set_category = @category = Category.find(params[:id])

  def month_param = current_month.strftime("%Y-%m")

  def category_params = params.require(:category).permit(:name, :budget_amount)

  def current_budget_amount
    Budget.find_by(category: @category, month: current_month)
          &.amount_cents&.then { |cents| BrlMoney.format(cents) }
  end

  # Persiste a categoria e, no mesmo mês em contexto, o orçado — as duas
  # coisas nascem juntas ou nenhuma nasce. Um orçado que não parseia, ou que
  # o model recusa (negativo, ou a reservada de cartão de crédito), não pode
  # deixar a categoria criada/renomeada com o orçado perdido em silêncio
  # (decisão pós-brief, ponto 1) — por isso a transação e o rollback
  # explícito em vez do `return` isolado do brief original.
  def save_category_and_budget(update: false)
    ok = false
    ActiveRecord::Base.transaction do
      category_ok = update ? @category.update(name: category_params[:name]) : @category.save
      if category_ok && save_budget
        ok = true
      else
        raise ActiveRecord::Rollback
      end
    end
    ok
  end

  # Orçado da categoria no mês em contexto. O form não mostra o campo para a
  # categoria "cartão de crédito" (o orçado dela é derivado das faturas), mas
  # um valor forjado/direto para ela não é ignorado: um orçado em branco
  # continua um no-op válido (é o que um submit normal do form manda), mas um
  # orçado presente segue o mesmo caminho de qualquer outra categoria e
  # esbarra em `Budget#not_on_credit_card_category` — 422, erro visível,
  # nenhuma escrita. Um valor que não parseia ganha erro próprio (não tem no
  # que a validação do Budget pegar, já que nem chega a virar amount_cents);
  # negativo e "cartão de crédito" são recusados pelo próprio Budget — o erro
  # dele é importado, não duplicado aqui.
  def save_budget
    amount = category_params[:budget_amount]
    return true if amount.blank?
    cents = BrlMoney.parse(amount)
    if cents.nil?
      @category.errors.add(:budget_amount, "não é um valor válido")
      return false
    end
    budget = Budget.find_or_initialize_by(category: @category, month: current_month)
    budget.amount_cents = cents
    return true if budget.save
    import_budget_errors(budget)
    false
  end

  # Mesma técnica do ExpenseEntry (app/models/expense_entry.rb): o campo do
  # form é "budget_amount", mas a validação mora em Budget#amount_cents — sem
  # o remap a mensagem fica presa numa chave que a view nunca olha.
  BUDGET_ERROR_ATTRIBUTE_REMAP = { amount_cents: :budget_amount }.freeze

  def import_budget_errors(budget)
    budget.errors.each do |error|
      @category.errors.import(error, attribute: BUDGET_ERROR_ATTRIBUTE_REMAP.fetch(error.attribute, error.attribute))
    end
  end
end
