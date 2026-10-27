# Where money sits: a bank account, or the carteira (cash). An account's balance
# is never stored — Budgeting::AccountBalances derives it on read.
#
# Two reserved accounts per person, like the reserved categories: "primary" (the
# bank account that holds saldo inicial, created as "Conta principal") and
# "wallet" (the carteira, where new dinheiro goes). Both are renamable, and can
# be neither archived nor deleted. Ordinary bank accounts carry a NULL role —
# filter with `where(role: [nil, ...])`, never `where.not(role:)`.
class Account < ApplicationRecord
  include OwnedByUser

  ROLES = %w[primary wallet].freeze

  # Same uniqueness caveat as Category: the validator queries `unscoped`, so the
  # scope on user_id is what keeps one person's roles from blocking another's.
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }, uniqueness: { scope: :user_id }, allow_nil: true
  validate :reserved_cannot_be_archived

  before_destroy :reject_destroy_of_reserved

  # Archived only leaves the pickers for new entries — never a default scope, for
  # the same reason as Card.active: an archived account's history and balance
  # keep counting in the total.
  scope :active, -> { where(archived_at: nil) }
  scope :banks, -> { where(role: [ nil, "primary" ]) }
  scope :ordered, -> {
    order(Arel.sql("CASE role WHEN 'primary' THEN 0 WHEN 'wallet' THEN 2 ELSE 1 END"), :name, :id)
  }

  def self.primary = find_by!(role: "primary")
  def self.wallet = find_by!(role: "wallet")

  def primary? = role == "primary"
  def wallet? = role == "wallet"
  def reserved? = role.present?

  def archived? = archived_at.present?
  def archive! = update!(archived_at: Time.current)
  def reactivate! = update!(archived_at: nil)

  private

  def reserved_cannot_be_archived
    errors.add(:base, "não pode ser arquivada") if reserved? && archived?
  end

  def reject_destroy_of_reserved
    return unless reserved?
    errors.add(:base, "não pode ser excluída")
    throw :abort
  end
end
