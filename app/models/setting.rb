class Setting < ApplicationRecord
  before_validation { self.first_month = first_month&.beginning_of_month }

  validates :first_month, presence: true
  validates :initial_balance_cents, numericality: { only_integer: true }
  validate :single_row, on: :create
  validate :first_month_not_after_existing_entries

  def self.instance = first

  private

  def single_row
    errors.add(:base, "já existe uma configuração") if Setting.exists?
  end

  # Mover first_month para depois de um lançamento já existente faria a
  # cadeia de saldos (BalanceChain) parar de contar esse lançamento em
  # silêncio. Mover para uma data anterior é inofensivo e continua livre.
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
