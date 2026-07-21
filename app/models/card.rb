class Card < ApplicationRecord
  has_many :card_schedules, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error
  has_many :installment_purchases, dependent: :restrict_with_error

  validates :name, presence: true
end
