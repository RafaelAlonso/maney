class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
    @reserved = Category.where.not(role: nil).order(:role)
    @first_month_input = @setting.first_month.strftime("%Y-%m")
    @initial_balance_input = BrlMoney.format(@setting.initial_balance_cents)
  end

  # initial_balance_cents ancora o Budgeting::BalanceChain do app inteiro —
  # todo saldo carregado de mês a mês descende dele. Um valor que não parseia
  # não pode virar 0 em silêncio (era o bug: BrlMoney.parse(...) || 0), por
  # isso o corte acontece aqui, antes de qualquer assign_attributes/save,
  # igual ao save_budget de CategoriesController.
  def update
    @setting = Setting.instance
    @first_month_input = params[:setting][:first_month]
    @initial_balance_input = params[:setting][:initial_balance]

    balance_cents = BrlMoney.parse(@initial_balance_input)
    if balance_cents.nil?
      @setting.errors.add(:initial_balance, "não é um valor válido")
      @reserved = Category.where.not(role: nil).order(:role)
      return render :edit, status: :unprocessable_entity
    end

    @setting.assign_attributes(first_month: parse_month(@first_month_input),
                               initial_balance_cents: balance_cents)
    if @setting.save
      redirect_to edit_settings_path, notice: "Configurações salvas."
    else
      @reserved = Category.where.not(role: nil).order(:role)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def parse_month(text)
    Date.strptime(text.to_s, "%Y-%m")
  rescue ArgumentError
    nil
  end
end
