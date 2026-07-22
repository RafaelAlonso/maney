# Form object do lançamento de gasto: decide entre Expense avulso e
# InstallmentPurchase (parcelado) e traduz valor BRL -> centavos. Toda regra
# financeira permanece nos models/motor; aqui só orquestração e parse.
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

  # `installment?` só olha a checkbox. Sem esta validação, `save`/`update`
  # despacham só nisso e `build_purchase` nunca lê `payment_method` — então
  # um submit que começou como crédito (cartão escolhido, parcelado marcado)
  # e foi trocado para débito/dinheiro antes do Salvar vira uma
  # InstallmentPurchase de verdade. `Budgeting::BalanceChain.current_balance`
  # só soma `payment_method: %w[debit cash]`, então esse gasto some da
  # cadeia de saldos por trás de um "Gasto lançado." — inflando pra sempre o
  # saldo carregado de todo mês seguinte. Rejeitar em vez de corrigir
  # sozinho: tanto descer para avulso quanto subir o método para crédito
  # jogariam fora o que o usuário pediu. Mesmo registro de
  # `Expense#card_matches_method`'s "só se aplica a gastos no crédito".
  #
  # Vai em :base de propósito. Em :installment o `full_message` vira
  # "Installment só se aplica…" — sem locale pt-BR, o prefixo é o nome
  # humanizado do atributo em inglês, e esta é a mensagem mais importante
  # da tela. Em :base a frase sai inteira em português.
  def installment_requires_credit
    return unless installment? && payment_method != "credit"
    errors.add(:base, "Parcelado só se aplica a gastos no crédito")
  end

  # Um category_id presente mas que não resolve mais (categoria excluída entre
  # o form ser aberto e o submit) cai em "outros" — mesma regra usada quando o
  # campo vem em branco e quando uma categoria é excluída de verdade.
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

  # `regenerate_installments!` é atômico por conta própria, mas isso só protege
  # a série. A transação aqui é o que mantém cabeçalho e série coerentes: sem
  # ela o purchase commita e só as parcelas voltam atrás, deixando um registro
  # que diz "5 parcelas de R$ 500" ao lado das 10 parcelas antigas de R$ 1.000.
  # Se o motor rejeitar a série nova, devolve o formulário com erro em vez de
  # deixar a exceção escapar como página de erro.
  def update_purchase(purchase)
    ok = false
    purchase.assign_attributes(name:, total_cents: amount_cents, date: date.presence, category:,
                               card_id: card_id.presence, installments_count:,
                               first_installment: first_installment.presence || 1)
    # Precisa ser lido aqui, com `changed` ainda refletindo a edição pendente
    # — depois do save bem-sucedido o dirty state já foi limpo.
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

  # A validação de total_cents vive na InstallmentPurchase (nome interno do
  # model), mas o campo do formulário é "amount" — sem este remapeamento a
  # mensagem fica presa numa chave que a view nunca olha.
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
