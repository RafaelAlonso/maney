class Expense < ApplicationRecord
  include OwnedByUser

  PAYMENT_METHODS = %w[credit debit cash].freeze

  belongs_to :category
  belongs_to :card, optional: true
  belongs_to :installment_purchase, optional: true
  belongs_to :account, optional: true

  before_validation :default_account

  validates :name, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }

  validate :card_matches_method
  validate :account_matches_method
  validate :credit_never_in_credit_card_category
  validate :installment_consistency
  validate :date_rules

  def installment? = installment_purchase_id.present?

  private

  def card_matches_method
    if payment_method == "credit"
      errors.add(:card, "é obrigatório para gastos no crédito") if card.nil?
    elsif card.present?
      errors.add(:card, "só se aplica a gastos no crédito")
    end
  end

  # Only fills a blank account, never overwrites one: a migrated dinheiro
  # expense sits in Conta principal and must stay there when edited. The
  # user-facing rules (débito picks a bank account, new dinheiro goes to the
  # carteira) live in ExpenseEntry; this is the model's fallback, like "outros".
  def default_account
    return if account.present?
    case payment_method
    when "debit" then self.account = Account.find_by(role: "primary")
    when "cash" then self.account = Account.find_by(role: "wallet")
    end
  end

  def account_matches_method
    if payment_method == "credit"
      errors.add(:account, "só se aplica a gastos no débito ou dinheiro") if account.present?
    elsif account.nil?
      errors.add(:account, "é obrigatória para gastos no débito ou dinheiro")
    elsif payment_method == "debit" && account.wallet?
      errors.add(:account, "carteira só para gastos em dinheiro")
    end
  end

  def credit_never_in_credit_card_category
    return unless payment_method == "credit" && category&.credit_card?
    errors.add(:category, "cartão de crédito não pode ser usada em gastos no crédito")
  end

  def installment_consistency
    if installment?
      errors.add(:installment_number, "é obrigatório numa parcela") if installment_number.nil?
      errors.add(:date, "parcela não tem data própria") if date.present?
      errors.add(:payment_method, "parcela é sempre no crédito") unless payment_method == "credit"
    elsif installment_number.present?
      errors.add(:installment_number, "só se aplica a parcelas")
    end
  end

  def date_rules
    return if installment?
    if date.nil?
      errors.add(:date, "é obrigatória")
      return
    end
    first = Setting.instance&.first_month
    errors.add(:date, "anterior ao primeiro mês — a linha do tempo começa nele") if first && date < first
  end
end
