# Form object for opening an account after setup. Only the Conta principal has
# a starting balance (saldo inicial, at the first month); an account opened
# later starts at 0, and "how much is in it today" arrives as a transfer from
# another account, dated today — so the account matches the bank while "saldo
# atual" doesn't move. No backdated balances, no "opened on" month in the chain.
class AccountOpening
  include ActiveModel::Model

  attr_accessor :name, :amount, :source_account_id
  attr_reader :account

  validate :amount_must_parse

  def save
    @account = Account.new(name:)
    return false unless [ valid?, account_valid? ].all?

    ActiveRecord::Base.transaction do
      @account.save!
      if amount_cents.positive?
        Transfer.create!(from_account: source_account, to_account: @account, amount_cents:,
                         date: Date.current, note: "saldo de abertura")
      end
    end
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |error| errors.import(error, attribute: error.attribute == :amount_cents ? :amount : error.attribute) }
    @account = Account.new(name:)
    false
  end

  # Blank means an empty account.
  def amount_cents = amount.blank? ? 0 : BrlMoney.parse(amount)

  private

  def account_valid?
    return true if @account.valid?
    @account.errors.each { |error| errors.import(error) }
    false
  end

  # Default scope: another person's id is simply not found; Conta principal
  # stands in, the same default the form pre-selects.
  def source_account = Account.find_by(id: source_account_id.presence) || Account.primary

  def amount_must_parse
    cents = amount_cents
    errors.add(:amount, "não é um valor válido") if cents.nil? || cents.negative?
  end
end
