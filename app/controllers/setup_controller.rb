class SetupController < ApplicationController
  skip_before_action :require_setup
  before_action { redirect_to root_path if Setting.instance }

  def new
    @setting = Setting.new(first_month: Date.current.beginning_of_month)
  end

  # Os três registros nascem juntos ou nenhum nasce. Sem a transação, uma
  # falha entre o Setting e as categorias deixa o app num estado que nada
  # mais detecta: `require_setup` passa (o Setting existe), mas a categoria
  # reservada "outros" não — e ela é o destino padrão de todo gasto sem
  # categoria e de toda categoria excluída. O app fica de pé quebrando em
  # qualquer lançamento.
  def create
    @setting = Setting.new(first_month: parse_month(params[:setup][:first_month]),
                           initial_balance_cents: BrlMoney.parse(params[:setup][:initial_balance]) || 0)
    created = ActiveRecord::Base.transaction do
      next false unless @setting.save
      Category.find_or_create_by!(role: "others") { |c| c.name = "outros" }
      Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" }
      true
    end

    if created
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
