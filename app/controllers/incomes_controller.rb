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

  # Mesma técnica do ExpenseEntry/CategoriesController#save_budget: parseia
  # antes de tocar `amount_cents`. Sem isso, um valor que não parseia caía
  # direto em `amount_cents: nil` e a numericality do model estourava na
  # coluna que a view nunca mostra ("Amount cents is not a number") com o
  # campo re-renderizado em branco — jogando fora o que o usuário digitou
  # (Fix 3, review final). `income.amount` (attr_accessor, não persistido)
  # guarda o texto exatamente como foi submetido, com sucesso ou falha no
  # parse, para o form sempre re-renderizar com ele.
  def assign_and_save(income)
    permitted = params.require(:income).permit(:name, :amount, :date)
    income.name = permitted[:name]
    income.date = permitted[:date]
    income.amount = permitted[:amount]
    cents = BrlMoney.parse(permitted[:amount])
    if cents.nil?
      # Roda as outras validações (nome, data) mesmo com o valor não
      # parseando, para não esconder um segundo erro real; só a mensagem de
      # `amount_cents` (presa numa coluna que a view não mostra) é trocada
      # pela nossa, no campo que o form de fato exibe.
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

  # A validação de `amount_cents > 0` (negativo, zero) mora no model, no
  # nome interno da coluna — mas o campo do form é "amount". Sem este remap
  # a mensagem fica presa numa chave que a view nunca olha. Mesma técnica do
  # ExpenseEntry (ERROR_ATTRIBUTE_REMAP) e do CategoriesController
  # (BUDGET_ERROR_ATTRIBUTE_REMAP).
  def remap_amount_cents_errors(income)
    amount_cents_errors = income.errors.where(:amount_cents).to_a
    return if amount_cents_errors.empty?
    income.errors.delete(:amount_cents)
    amount_cents_errors.each { |error| income.errors.import(error, attribute: :amount) }
  end
end
