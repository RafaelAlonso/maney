class Card < ApplicationRecord
  has_many :card_schedules, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error
  has_many :installment_purchases, dependent: :restrict_with_error

  validates :name, presence: true

  # Editar os dias nunca reescreve a vigência antiga: cria uma nova valendo do
  # início da janela aberta hoje — faturas já fechadas seguem derivadas da
  # antiga, e a fronteira é sempre uma data real de fechamento (ver
  # Budgeting::StatementAttribution.window_start). Devolve a linha SEM salvar,
  # ou nil se os dias pedidos já são os vigentes.
  def reschedule(closing_day:, due_day:, today: Date.current)
    wanted = [closing_day.to_i, due_day.to_i]
    current = Budgeting::Schedule.for(card: self, date: today)
    return nil if [current.closing_day, current.due_day] == wanted

    row = amendable_schedule(today) ||
          card_schedules.find_or_initialize_by(
            valid_from: Budgeting::StatementAttribution.window_start(card: self, date: today)
          )
    row.assign_attributes(closing_day: wanted[0], due_day: wanted[1])
    row
  end

  private

  # Corrigir os dias no mesmo dia em que a vigência foi criada amenda aquela
  # linha em vez de empilhar outra: a primeira edição já moveu as fronteiras,
  # então a segunda cairia numa fronteira diferente e deixaria para trás uma
  # vigência de vida curta que ninguém pediu.
  def amendable_schedule(today)
    rows = card_schedules.order(:valid_from).to_a
    return nil if rows.size < 2

    latest = rows.last
    latest if latest.valid_from <= today && latest.created_at&.to_date == today
  end
end
