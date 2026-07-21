class Budget < ApplicationRecord
  belongs_to :category

  before_validation { self.month = month&.beginning_of_month }

  validates :month, presence: true, uniqueness: { scope: :category_id }
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :not_on_credit_card_category

  private

  def not_on_credit_card_category
    return unless category&.credit_card?
    errors.add(:category, "cartão de crédito não aceita orçado manual — o orçado é derivado das faturas")
  end
end
