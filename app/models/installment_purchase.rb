class InstallmentPurchase < ApplicationRecord
  include OwnedByUser

  belongs_to :card
  belongs_to :category
  has_many :expenses, dependent: :destroy

  validates :name, presence: true
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
  # 120 = ten years of monthly installments — well beyond the 12x/24x that
  # Brazilian cards actually offer, but enough to catch a stray extra digit
  # (1200 instead of 120) without getting in anyone's way.
  validates :installments_count, numericality: {
    only_integer: true, greater_than_or_equal_to: 2, less_than_or_equal_to: 120,
    message: "deve ter entre 2 e 120 parcelas"
  }
  validates :first_installment, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :date, presence: true
  validate :first_installment_within_range
  validate :category_not_credit_card
  validate :date_within_timeline
  validate :total_covers_installments

  after_create :generate_installments

  # Recomputes the whole series after an edit — wipes and regenerates via the
  # engine. The transaction lives here, not in the caller: whoever destroys and
  # recreates is who must guarantee that a mid-way failure doesn't leave the
  # series half-built — you can't trust every caller to remember to wrap it.
  def regenerate_installments!
    transaction do
      expenses.destroy_all
      generate_installments
    end
  end

  # Attributes that `generate_installments` actually consumes: name (composes
  # each installment's name), total and installment count (split the amount via
  # Budgeting::InstallmentSplit), first installment (defines the generated
  # range) and card/category (copied onto each expense). `date` is left out on
  # purpose — every installment is born with `date: nil`; competence and
  # statement attribution are derived later from the purchase date
  # (Budgeting::Competence, Budgeting::StatementAttribution), not stored on the
  # row. Changing the purchase date changes how the existing installments are
  # *read*, not what was *written* to them — so it's not a reason to destroy and
  # recreate the series.
  SERIES_INPUT_ATTRIBUTES = %w[name total_cents installments_count first_installment card_id category_id].freeze

  # Call after `assign_attributes` and before saving: `changed` only reflects
  # the pending edit until the save persists and clears the dirty state.
  def series_inputs_changed?
    changed.intersect?(SERIES_INPUT_ATTRIBUTES)
  end

  private

  def first_installment_within_range
    return if first_installment.nil? || installments_count.nil?
    return if first_installment <= installments_count
    errors.add(:first_installment, "deve estar entre 1 e o número de parcelas")
  end

  def category_not_credit_card
    return unless category&.credit_card?
    errors.add(:category, "cartão de crédito não pode ser usada em compras no crédito")
  end

  def date_within_timeline
    first = Setting.instance&.first_month
    return if date.nil? || first.nil? || date >= first
    errors.add(:date, "anterior ao primeiro mês — a linha do tempo começa nele")
  end

  def total_covers_installments
    return if total_cents.nil? || installments_count.nil?
    return if total_cents >= installments_count
    errors.add(:total_cents, "não pode ser menor que o número de parcelas — cada parcela ficaria com menos de 1 centavo")
  end

  def generate_installments
    Budgeting::InstallmentSplit.call(total_cents:, count: installments_count, first: first_installment).each do |part|
      expenses.create!(
        name: "#{name} #{part.number}/#{installments_count}",
        amount_cents: part.amount_cents,
        payment_method: "credit",
        card:, category:,
        installment_number: part.number,
        date: nil
      )
    end
  end
end
