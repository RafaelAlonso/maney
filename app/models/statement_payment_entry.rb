# Form object for paying a card bill ("pagar"): which account, how much, when.
# The payment stays an Expense — débito (or dinheiro from the carteira) in the
# reserved credit-card category — so every aggregate that already reads bill
# payments keeps working; what's new is the link to the statement it pays
# (card + nominal closing, see Budgeting::StatementPayments).
class StatementPaymentEntry
  include ActiveModel::Model

  attr_accessor :account_id, :amount, :date
  attr_reader :record

  validate :amount_must_parse
  validate :account_must_exist

  def self.from(expense)
    new(account_id: expense.account_id, amount: BrlMoney.format(expense.amount_cents), date: expense.date)
  end

  def save(card:, statement:)
    return false unless valid?
    @record = Expense.new(name: "fatura #{card.name} · vence #{statement.effective_due.strftime('%d/%m')}",
                          category: Category.find_by!(role: "credit_card"),
                          statement_card: card, statement_closing_on: statement.nominal_closing)
    persist
  end

  def update(expense)
    @record = expense
    return false unless valid?
    persist
  end

  private

  def amount_cents = BrlMoney.parse(amount)

  # Default scope: another person's id is simply not found.
  def account = Account.find_by(id: account_id.presence)

  def persist
    @record.assign_attributes(account:, amount_cents:, date: date.presence,
                              payment_method: account.wallet? ? "cash" : "debit")
    return true if @record.save
    @record.errors.each do |error|
      errors.import(error, attribute: error.attribute == :amount_cents ? :amount : error.attribute)
    end
    false
  end

  def amount_must_parse
    errors.add(:amount, "não é um valor válido") if amount_cents.nil? || amount_cents <= 0
  end

  def account_must_exist
    errors.add(:account_id, "escolha a conta") if account.nil?
  end
end
