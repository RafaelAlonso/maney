class Income < ApplicationRecord
  include OwnedByUser

  # Not persisted: holds the text exactly as the user typed it (e.g. "abc",
  # "0,00") so the form can re-render with it after a 422 — without this the
  # field would fall back to `amount_cents` (which is nil when the parse fails)
  # and the user would see an empty field, having to retype everything. Same
  # technique as `ExpenseEntry#amount` (app/models/expense_entry.rb).
  attr_accessor :amount

  validates :name, presence: true
  validates :amount_cents, numericality: { only_integer: true, greater_than: 0 }
  validates :date, presence: true
  validate :date_within_timeline

  private

  def date_within_timeline
    first = Setting.instance&.first_month
    return if date.nil? || first.nil? || date >= first
    errors.add(:date, "anterior ao primeiro mês — a linha do tempo começa em #{first.strftime('%m/%Y')}")
  end
end
