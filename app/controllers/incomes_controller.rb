class IncomesController < ApplicationController
  before_action :set_income, only: %i[edit update destroy]

  def index
    @incomes = Income.where(date: current_month.all_month).order(:date, :name)
    @carried_cents = Budgeting::BalanceChain.carried_into(month: current_month)
    @first_month = current_month == Setting.instance.first_month
  end

  def new
    @income = Income.new(date: Date.current)
  end

  def create
    @income = Income.new
    if assign_and_save(@income)
      redirect_to incomes_path(month: @income.date.strftime("%Y-%m")), notice: "Ganho lançado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if assign_and_save(@income)
      redirect_to incomes_path(month: @income.date.strftime("%Y-%m")), notice: "Ganho atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @income.destroy
    redirect_to incomes_path, notice: "Ganho excluído."
  end

  private

  def set_income = @income = Income.find(params[:id])

  # Same technique as ExpenseEntry/CategoriesController#save_budget: parse before
  # touching `amount_cents`. Without this, a value that doesn't parse fell
  # straight into `amount_cents: nil` and the model's numericality blew up on the
  # column the view never shows ("Amount cents is not a number") with the field
  # re-rendered blank — throwing away what the user typed (Fix 3, final review).
  # `income.amount` (attr_accessor, not persisted) holds the text exactly as it
  # was submitted, whether the parse succeeds or fails, so the form always
  # re-renders with it.
  def assign_and_save(income)
    permitted = params.require(:income).permit(:name, :amount, :date)
    income.name = permitted[:name]
    income.date = permitted[:date]
    income.amount = permitted[:amount]
    cents = BrlMoney.parse(permitted[:amount])
    if cents.nil?
      # Run the other validations (name, date) even with the amount not parsing,
      # so a second real error isn't hidden; only the `amount_cents` message
      # (stuck on a column the view doesn't show) is swapped for ours, on the
      # field the form actually displays.
      income.valid?
      income.errors.delete(:amount_cents)
      income.errors.add(:amount, "não é um valor válido")
      return false
    end
    income.amount_cents = cents
    return true if income.save
    remap_amount_cents_errors(income)
    false
  end

  # The `amount_cents > 0` validation (negative, zero) lives on the model, under
  # the column's internal name — but the form field is "amount". Without this
  # remap the message stays stuck on a key the view never looks at. Same technique
  # as ExpenseEntry (ERROR_ATTRIBUTE_REMAP) and CategoriesController
  # (BUDGET_ERROR_ATTRIBUTE_REMAP).
  def remap_amount_cents_errors(income)
    amount_cents_errors = income.errors.where(:amount_cents).to_a
    return if amount_cents_errors.empty?
    income.errors.delete(:amount_cents)
    amount_cents_errors.each { |error| income.errors.import(error, attribute: :amount) }
  end
end
