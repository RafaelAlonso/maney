# Form object do lançamento de gasto: decide entre Expense avulso e
# InstallmentPurchase (parcelado) e traduz valor BRL -> centavos. Toda regra
# financeira permanece nos models/motor; aqui só orquestração e parse.
class ExpenseEntry
  include ActiveModel::Model

  attr_accessor :name, :amount, :date, :category_id, :payment_method,
                :card_id, :installment, :installments_count, :first_installment
  attr_reader :record

  validate :amount_must_parse

  def self.from(source)
    case source
    when InstallmentPurchase
      new(name: source.name, amount: BrlMoney.format(source.total_cents), date: source.date,
          category_id: source.category_id, payment_method: "credit", card_id: source.card_id,
          installment: "1", installments_count: source.installments_count,
          first_installment: source.first_installment)
    else
      new(name: source.name, amount: BrlMoney.format(source.amount_cents), date: source.date,
          category_id: source.category_id, payment_method: source.payment_method,
          card_id: source.card_id)
    end
  end

  def installment? = installment.to_s == "1"

  def save
    return false unless valid?
    @record = installment? ? build_purchase : Expense.new(expense_attributes)
    persist(@record)
  end

  def update(source)
    return false unless valid?
    @record = source
    case source
    when InstallmentPurchase then update_purchase(source)
    else
      source.assign_attributes(expense_attributes)
      persist(source)
    end
  end

  private

  def amount_cents = BrlMoney.parse(amount)

  def amount_must_parse
    errors.add(:amount, "não é um valor válido") if amount_cents.nil? || amount_cents <= 0
  end

  def category
    category_id.present? ? Category.find(category_id) : Category.find_by!(role: "others")
  end

  def expense_attributes
    { name:, amount_cents:, date: date.presence, category:, payment_method:,
      card_id: payment_method == "credit" ? card_id.presence : nil }
  end

  def build_purchase
    InstallmentPurchase.new(name:, total_cents: amount_cents, date: date.presence, category:,
                            card_id: card_id.presence, installments_count:,
                            first_installment: first_installment.presence || 1)
  end

  def update_purchase(purchase)
    purchase.assign_attributes(name:, total_cents: amount_cents, date: date.presence, category:,
                               card_id: card_id.presence, installments_count:,
                               first_installment: first_installment.presence || 1)
    ok = false
    ActiveRecord::Base.transaction do
      ok = persist(purchase)
      purchase.regenerate_installments! if ok
      raise ActiveRecord::Rollback unless ok
    end
    purchase.reload unless ok
    ok
  end

  def persist(model)
    return true if model.save
    model.errors.each { |error| errors.import(error) }
    false
  end
end
