class SetupController < ApplicationController
  skip_before_action :require_setup
  before_action { redirect_to root_path if Setting.instance }

  def new
    @setting = Setting.new(first_month: Date.current.beginning_of_month)
  end

  def create
    @setting = Setting.new(first_month: parse_month(params[:setup][:first_month]),
                           initial_balance_cents: BrlMoney.parse(params[:setup][:initial_balance]) || 0)
    if @setting.save
      Category.find_or_create_by!(role: "others") { |c| c.name = "outros" }
      Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" }
      redirect_to root_path, notice: "Tudo pronto — pode começar a lançar."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def parse_month(text)
    Date.strptime(text.to_s, "%Y-%m")
  rescue ArgumentError
    nil
  end
end
