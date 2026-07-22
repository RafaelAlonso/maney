class Income < ApplicationRecord
  # Não persistido: guarda o texto exatamente como o usuário digitou (ex.:
  # "abc", "0,00") para o form re-renderizar com ele depois de um 422 — sem
  # isso o campo cairia de volta em `amount_cents` (que fica nil quando o
  # parse falha) e o usuário veria o campo vazio, tendo que redigitar tudo.
  # Mesma técnica do `ExpenseEntry#amount` (app/models/expense_entry.rb).
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
