# Money moving between two of one person's own accounts — a saque is a transfer
# from a bank account to the carteira. Never spending and never income: no
# category, chart, Análise, MonthSummary total or Ganhos reads this table. Only
# Budgeting::AccountBalances does, and across all accounts a transfer nets to
# zero, so "saldo atual" never moves.
class Transfer < ApplicationRecord
  include OwnedByUser

  # Not persisted: the amount exactly as typed, so the form re-renders with it
  # after a 422 — same technique as Income#amount.
  attr_accessor :amount

  belongs_to :from_account, class_name: "Account"
  belongs_to :to_account, class_name: "Account"

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :date, presence: true
  validate :distinct_accounts
  validate :date_within_timeline

  private

  def distinct_accounts
    return if from_account.nil? || to_account.nil?
    errors.add(:to_account, "deve ser diferente da origem") if from_account == to_account
  end

  def date_within_timeline
    first = Setting.instance&.first_month
    return if date.nil? || first.nil? || date >= first
    errors.add(:date, "anterior ao primeiro mês — a linha do tempo começa nele")
  end
end
