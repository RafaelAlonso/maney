class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]

  def index
    @categories = Category.order(:name)
    @budgets = Budget.where(month: current_month).index_by(&:category_id)
  end

  # The charts read the year of the month in context — the month nav above them
  # is the only year control this screen has, by design (there is no year
  # picker). The breakdown is handed the very collection the list renders, so
  # the pie and the list can never disagree about what the month contains.
  def show
    @summary = Budgeting::MonthSummary.new(month: current_month)
    @siblings = Category.order(:name).to_a
    @expenses = Budgeting::MonthEntries.expenses(month: current_month, category: @category)
    @statements = Budgeting::StatementSet.labels_for(@expenses)
    @category_year = Budgeting::CategoryYear.new(category: @category, year: current_month.year)
    palette = Analysis::Palette.new
    @year_chart = Analysis::CategorySpendingChart.new(@category_year, palette:)
    @breakdown = Analysis::CategoryBreakdownChart.new(expenses: @expenses, category: @category,
                                                      month: current_month, palette:)
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

  # Deleting moves the expenses (and installment purchases) to the default one —
  # the notice with the count lives in the list's turbo_confirm.
  def destroy
    if @category.reserved?
      redirect_to categories_path(month: month_param), alert: "Categoria reservada não pode ser excluída."
      return
    end
    default = Category.find_by!(role: "others")
    ActiveRecord::Base.transaction do
      @category.expenses.update_all(category_id: default.id)
      InstallmentPurchase.where(category: @category).update_all(category_id: default.id)
      @category.reload.destroy!
    end
    redirect_to categories_path(month: month_param), notice: "Categoria excluída; gastos movidos para #{default.name}."
  end

  private

  def set_category = @category = Category.find(params[:id])

  def category_params = params.require(:category).permit(:name, :budget_amount)

  def current_budget_amount
    Budget.find_by(category: @category, month: current_month)
          &.amount_cents&.then { |cents| BrlMoney.format(cents) }
  end

  # Persists the category and, in the same month in context, the budget — the two
  # are born together or neither is. A budget that doesn't parse, or that the
  # model rejects (negative, or the reserved credit-card one), must not leave the
  # category created/renamed with the budget silently lost (post-brief decision,
  # point 1) — hence the transaction and the explicit rollback instead of the
  # isolated `return` in the original brief.
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

  # The category's budget in the month in context. The form doesn't show the
  # field for the "cartão de crédito" category (its budget is derived from the
  # statements), but a forged/direct value for it isn't ignored: a blank budget
  # stays a valid no-op (what a normal form submit sends), but a present budget
  # follows the same path as any other category and hits
  # `Budget#not_on_credit_card_category` — 422, visible error, no write. A value
  # that doesn't parse gets its own error (there's nothing for the Budget
  # validation to catch, since it never becomes amount_cents); negative and the
  # "cartão de crédito" category are rejected by Budget itself — its error is
  # imported, not duplicated here.
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

  # Same technique as ExpenseEntry (app/models/expense_entry.rb): the form field
  # is "budget_amount", but the validation lives on Budget#amount_cents — without
  # the remap the message stays stuck on a key the view never looks at.
  BUDGET_ERROR_ATTRIBUTE_REMAP = { amount_cents: :budget_amount }.freeze

  def import_budget_errors(budget)
    budget.errors.each do |error|
      @category.errors.import(error, attribute: BUDGET_ERROR_ATTRIBUTE_REMAP.fetch(error.attribute, error.attribute))
    end
  end
end
