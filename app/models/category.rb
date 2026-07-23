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

  # Removing or changing a reserved category's role is blocked; renaming stays
  # free (decisions: a reserved category is "not deletable, renamable").
  #
  # Promoting an ordinary category to reserved stays allowed on purpose: with the
  # seeds run both roles already exist and the uniqueness validation blocks the
  # promotion, so this is only reachable on a database without seeds — which is
  # exactly the recovery path. If there's ever a categories screen, revisit:
  # promoting "mercado" to credit card reinterprets its whole history and, by
  # this same validation, would be irreversible.
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
