class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
    @reserved = Category.where.not(role: nil).order(:role)
  end

  def update
    @setting = Setting.instance
    @setting.assign_attributes(first_month: parse_month(params[:setting][:first_month]),
                               initial_balance_cents: BrlMoney.parse(params[:setting][:initial_balance]) || 0)
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
