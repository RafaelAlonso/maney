class Setting < ApplicationRecord
  before_validation { self.first_month = first_month&.beginning_of_month }

  validates :first_month, presence: true
  validates :initial_balance_cents, numericality: { only_integer: true }
  validate :single_row, on: :create

  def self.instance = first

  private

  def single_row
    errors.add(:base, "já existe uma configuração") if Setting.exists?
  end
end
