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

  # Tirar ou trocar o papel de uma reservada é bloqueado; renomear continua
  # livre (decisões: reservada é "não excluível, renomeável").
  #
  # Promover uma categoria comum a reservada continua permitido de propósito:
  # com as seeds rodadas os dois papéis já existem e a validação de unicidade
  # barra a promoção, então isso só é alcançável num banco sem seeds — onde
  # é justamente o caminho de recuperação. Se algum dia houver tela de
  # categorias, reveja: promover "mercado" a cartão de crédito reinterpreta
  # todo o histórico dela e, por esta mesma validação, não teria volta.
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
