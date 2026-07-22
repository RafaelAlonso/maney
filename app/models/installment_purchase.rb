class InstallmentPurchase < ApplicationRecord
  belongs_to :card
  belongs_to :category
  has_many :expenses, dependent: :destroy

  validates :name, presence: true
  validates :total_cents, numericality: { only_integer: true, greater_than: 0 }
  # 120 = dez anos de parcelas mensais — bem além dos 12x/24x que os cartões
  # brasileiros oferecem de fato, mas o suficiente para barrar um dígito
  # sobrando (1200 no lugar de 120) sem incomodar ninguém de verdade.
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

  # Recalcula a série inteira após edição — apaga e regenera pelo motor.
  # A transação vive aqui, não em quem chama: quem destrói e recria é quem
  # tem que garantir que uma falha no meio do caminho não deixe a série pela
  # metade — não dá para confiar que todo chamador vai lembrar de embrulhar.
  def regenerate_installments!
    transaction do
      expenses.destroy_all
      generate_installments
    end
  end

  # Atributos que `generate_installments` de fato consome: nome (compõe o
  # nome de cada parcela), total e número de parcelas (dividem o valor via
  # Budgeting::InstallmentSplit), parcela inicial (define o intervalo
  # gerado) e cartão/categoria (copiados para cada gasto). `date` fica de
  # fora de propósito — toda parcela nasce com `date: nil`; competência e
  # atribuição de fatura são derivadas depois a partir da data da compra
  # (Budgeting::Competence, Budgeting::StatementAttribution), não
  # armazenadas na linha. Mudar a data da compra muda como as parcelas já
  # existentes são *lidas*, não o que foi *gravado* nelas — então não é um
  # motivo para destruir e recriar a série.
  SERIES_INPUT_ATTRIBUTES = %w[name total_cents installments_count first_installment card_id category_id].freeze

  # Chamar depois de `assign_attributes` e antes de salvar: `changed` só
  # reflete a edição pendente até o save persistir e limpar o dirty state.
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
