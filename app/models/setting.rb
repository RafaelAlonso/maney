class Setting < ApplicationRecord
  include OwnedByUser

  before_validation { self.first_month = first_month&.beginning_of_month }

  validates :first_month, presence: true
  validates :initial_balance_cents, numericality: { only_integer: true }
  validates :alert_threshold_percent,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 100 }
  validate :single_row, on: :create
  validate :first_month_not_after_existing_entries

  def self.instance = first

  private

  def single_row
    errors.add(:base, "já existe uma configuração") if Setting.exists?
  end

  # Moving first_month past an existing entry would silently make the balance
  # chain (BalanceChain) stop counting that entry. Moving it to an earlier date
  # is harmless and stays unrestricted.
  def first_month_not_after_existing_entries
    return if first_month.nil?

    earliest = earliest_entry_month
    return if earliest.nil? || first_month <= earliest

    errors.add(:first_month,
                "não pode ser posterior a #{earliest.strftime('%m/%Y')} — já existem lançamentos nesse mês")
  end

  def earliest_entry_month
    dates = [
      Income.minimum(:date),
      Expense.where.not(date: nil).minimum(:date),
      InstallmentPurchase.minimum(:date)
    ].compact
    return nil if dates.empty?

    dates.min.beginning_of_month
  end
end
