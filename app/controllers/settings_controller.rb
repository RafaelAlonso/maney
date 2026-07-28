class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
    @reserved = Category.where.not(role: nil).order(:role)
    @first_month_input = @setting.first_month.strftime("%Y-%m")
    @initial_balance_input = BrlMoney.format(@setting.initial_balance_cents)
    @alert_threshold_input = @setting.alert_threshold_percent
  end

  # initial_balance_cents anchors the whole app's Budgeting::BalanceChain — every
  # month-to-month carried balance descends from it. A value that doesn't parse
  # must not silently become 0 (that was the bug: BrlMoney.parse(...) || 0), so
  # the cutoff happens here, before any assign_attributes/save, just like
  # CategoriesController's save_budget.
  def update
    @setting = Setting.instance
    @first_month_input = params[:setting][:first_month]
    @initial_balance_input = params[:setting][:initial_balance]
    @alert_threshold_input = params[:setting][:alert_threshold_percent]

    balance_cents = BrlMoney.parse(@initial_balance_input)
    if balance_cents.nil?
      @setting.errors.add(:initial_balance, "não é um valor válido")
      @reserved = Category.where.not(role: nil).order(:role)
      return render :edit, status: :unprocessable_entity
    end

    @setting.assign_attributes(first_month: parse_month(@first_month_input),
                               initial_balance_cents: balance_cents,
                               alert_threshold_percent: @alert_threshold_input)
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
