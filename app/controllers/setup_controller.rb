class SetupController < ApplicationController
  skip_before_action :require_setup
  before_action { redirect_to root_path if Setting.instance }

  def new
    @setting = Setting.new(first_month: Date.current.beginning_of_month)
    @first_month_input = @setting.first_month.strftime("%Y-%m")
    @initial_balance_input = "0,00"
  end

  # The three records are born together or none is. Without the transaction, a
  # failure between the Setting and the categories leaves the app in a state
  # nothing else detects: `require_setup` passes (the Setting exists), but the
  # reserved "outros" category doesn't — and it's the default destination for
  # every expense without a category and every deleted category. The app stays up
  # while breaking on any entry.
  #
  # initial_balance_cents anchors the whole app's Budgeting::BalanceChain; a value
  # that doesn't parse must not silently become 0 (that was the bug:
  # BrlMoney.parse(...) || 0). The cutoff happens before any Setting.new with
  # initial_balance_cents and before the transaction — nothing is created.
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
