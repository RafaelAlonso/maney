class InstallmentPurchase < ApplicationRecord
  belongs_to :card
  belongs_to :category
  has_many :expenses, dependent: :destroy

  validates :name, presence: true
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :installments_count, numericality: { only_integer: true, greater_than_or_equal_to: 2 }
  validates :first_installment, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :date, presence: true
  validate :first_installment_within_range
  validate :category_not_credit_card
  validate :date_within_timeline

  after_create :generate_installments

  private

  def first_installment_within_range
    return if first_installment.nil? || installments_count.nil?
    return if first_installment <= installments_count
    errors.add(:first_installment, "deve estar entre 1 e o número de parcelas")
  end

  def category_not_credit_card
    return unless category&.credit_card?
    errors.add(:category, "cartão de crédito não pode ser usada em compras no crédito")
  end

  def date_within_timeline
    first = Setting.instance&.first_month
    return if date.nil? || first.nil? || date >= first
    errors.add(:date, "anterior ao primeiro mês — a linha do tempo começa nele")
  end

  def generate_installments
    Budgeting::InstallmentSplit.call(total_cents:, count: installments_count, first: first_installment).each do |part|
      expenses.create!(
        name: "#{name} #{part.number}/#{installments_count}",
        amount_cents: part.amount_cents,
        payment_method: "credit",
        card:, category:,
        installment_number: part.number,
        date: nil
      )
    end
  end
end
