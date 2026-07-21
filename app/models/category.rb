class Category < ApplicationRecord
  ROLES = %w[others credit_card].freeze

  has_many :budgets, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error

  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }, uniqueness: true, allow_nil: true

  def credit_card? = role == "credit_card"
  def reserved? = role.present?
end
