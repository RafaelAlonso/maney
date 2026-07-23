# Form object for entering an expense: decides between a standalone Expense and
# an InstallmentPurchase (installment) and converts a BRL amount -> cents. All
# financial rules stay in the models/engine; here it's only orchestration and parsing.
class ExpenseEntry
  include ActiveModel::Model

  attr_accessor :name, :amount, :date, :category_id, :payment_method,
                :card_id, :installment, :installments_count, :first_installment
  attr_reader :record

  validate :amount_must_parse
  validate :installment_requires_credit

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

  # `installment?` only looks at the checkbox. Without this validation,
  # `save`/`update` dispatch on that alone and `build_purchase` never reads
  # `payment_method` — so a submit that started as credit (card chosen,
  # installment checked) and was switched to debit/cash before Save becomes a
  # real InstallmentPurchase. `Budgeting::BalanceChain.current_balance` only
  # sums `payment_method: %w[debit cash]`, so that expense vanishes from the
  # balance chain behind a "Gasto lançado." — permanently inflating every later
  # month's carried balance. Reject instead of fixing it silently: both
  # downgrading to standalone and upgrading the method to credit would throw
  # away what the user asked for. Same rationale as
  # `Expense#card_matches_method`'s "só se aplica a gastos no crédito".
  #
  # Goes on :base on purpose. On :installment the `full_message` becomes
  # "Installment só se aplica…" — without a pt-BR locale, the prefix is the
  # humanized attribute name in English, and this is the most important message
  # on the screen. On :base the whole sentence comes out in Portuguese.
  def installment_requires_credit
    return unless installment? && payment_method != "credit"
    errors.add(:base, "Parcelado só se aplica a gastos no crédito")
  end

  # A category_id that is present but no longer resolves (category deleted
  # between the form opening and the submit) falls back to the "outros" category
  # — the same rule used when the field comes in blank and when a category is
  # genuinely deleted.
  def category
    return Category.find_by!(role: "others") if category_id.blank?
    Category.find_by(id: category_id) || Category.find_by!(role: "others")
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

  # `regenerate_installments!` is atomic on its own, but that only protects the
  # series. The transaction here is what keeps the header and series consistent:
  # without it the purchase commits and only the installments roll back, leaving
  # a record that says "5 installments of R$ 500" next to the 10 old installments of
  # R$ 1.000. If the engine rejects the new series, return the form with an error
  # instead of letting the exception escape as an error page.
  def update_purchase(purchase)
    ok = false
    purchase.assign_attributes(name:, total_cents: amount_cents, date: date.presence, category:,
                               card_id: card_id.presence, installments_count:,
                               first_installment: first_installment.presence || 1)
    # Must be read here, while `changed` still reflects the pending edit —
    # after a successful save the dirty state has already been cleared.
    regenerate = purchase.series_inputs_changed?
    ActiveRecord::Base.transaction do
      ok = persist(purchase)
      purchase.regenerate_installments! if ok && regenerate
    end
    ok
  rescue ActiveRecord::RecordInvalid => e
    import_errors(e.record)
    ok = false
  ensure
    purchase.reload unless ok
  end

  # The total_cents validation lives on InstallmentPurchase (the model's
  # internal name), but the form field is "amount" — without this remap the
  # message stays stuck on a key the view never looks at.
  ERROR_ATTRIBUTE_REMAP = { total_cents: :amount }.freeze
  private_constant :ERROR_ATTRIBUTE_REMAP

  def persist(model)
    return true if model.save
    import_errors(model)
    false
  end

  def import_errors(model)
    model.errors.each do |error|
      errors.import(error, attribute: ERROR_ATTRIBUTE_REMAP.fetch(error.attribute, error.attribute))
    end
  end
end
