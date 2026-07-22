class SetupController < ApplicationController
  skip_before_action :require_setup
  before_action { redirect_to root_path if Setting.instance }

  def new
    @setting = Setting.new(first_month: Date.current.beginning_of_month)
    @first_month_input = @setting.first_month.strftime("%Y-%m")
    @initial_balance_input = "0,00"
  end

  # Os três registros nascem juntos ou nenhum nasce. Sem a transação, uma
  # falha entre o Setting e as categorias deixa o app num estado que nada
  # mais detecta: `require_setup` passa (o Setting existe), mas a categoria
  # reservada "outros" não — e ela é o destino padrão de todo gasto sem
  # categoria e de toda categoria excluída. O app fica de pé quebrando em
  # qualquer lançamento.
  #
  # initial_balance_cents ancora o Budgeting::BalanceChain do app inteiro; um
  # valor que não parseia não pode virar 0 em silêncio (era o bug:
  # BrlMoney.parse(...) || 0). O corte acontece antes de qualquer Setting.new
  # com initial_balance_cents e antes da transação — nada é criado.
  def create
    @first_month_input = params[:setup][:first_month]
    @initial_balance_input = params[:setup][:initial_balance]

    balance_cents = BrlMoney.parse(@initial_balance_input)
    if balance_cents.nil?
      @setting = Setting.new
      @setting.errors.add(:initial_balance, "não é um valor válido")
      return render :new, status: :unprocessable_entity
    end

    @setting = Setting.new(first_month: parse_month(@first_month_input),
                           initial_balance_cents: balance_cents)
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
