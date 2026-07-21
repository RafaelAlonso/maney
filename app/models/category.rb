class Category < ApplicationRecord
  ROLES = %w[others credit_card].freeze

  has_many :budgets, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error

  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }, uniqueness: true, allow_nil: true
  validate :reserved_role_cannot_change

  before_destroy :reject_destroy_of_reserved_role

  def credit_card? = role == "credit_card"
  def reserved? = role.present?

  private

  def reserved_role_cannot_change
    return unless persisted?
    return unless role_was.present? && role_changed?
    errors.add(:role, "de categoria reservada não pode ser alterado ou removido")
  end

  def reject_destroy_of_reserved_role
    return if role.blank?
    errors.add(:base, "categoria reservada não pode ser excluída")
    throw :abort
  end
end
