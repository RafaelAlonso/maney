class Income < ApplicationRecord
  validates :name, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :date, presence: true
  validate :date_within_timeline

  private

  def date_within_timeline
    first = Setting.instance&.first_month
    return if date.nil? || first.nil? || date >= first
    errors.add(:date, "anterior ao primeiro mês — a linha do tempo começa em #{first.strftime('%m/%Y')}")
  end
end
