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
    @income = Income.new(income_attributes)
    if @income.save
      redirect_to incomes_path(month: @income.date.strftime("%Y-%m")), notice: "Ganho lançado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @income.update(income_attributes)
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

  def income_attributes
    permitted = params.require(:income).permit(:name, :amount, :date)
    { name: permitted[:name], date: permitted[:date], amount_cents: BrlMoney.parse(permitted[:amount]) }
  end
end
