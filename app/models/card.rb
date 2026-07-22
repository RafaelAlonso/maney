class Card < ApplicationRecord
  has_many :card_schedules, dependent: :destroy
  has_many :expenses, dependent: :restrict_with_error
  has_many :installment_purchases, dependent: :restrict_with_error

  validates :name, presence: true

  # Editar os dias nunca reescreve a vigência antiga: cria uma nova valendo do
  # início da janela aberta hoje — faturas já fechadas seguem derivadas da
  # antiga, e a fronteira é sempre uma data real de fechamento (ver
  # Budgeting::StatementAttribution.window_start). Devolve nil se os dias
  # pedidos já são os vigentes.
  #
  # A linha devolvida costuma ser nova, mas pode vir persistida: quando a
  # fronteira coincide com uma vigência que já existe (segunda correção na
  # mesma janela, ou cartão cuja linha do tempo começa no futuro), a própria
  # linha existente volta suja. Quem chama salva sempre — nunca ramifique em
  # `persisted?` / `new_record?`.
  def reschedule(closing_day:, due_day:, today: Date.current)
    wanted = [closing_day.to_i, due_day.to_i]
    current = Budgeting::Schedule.for(card: self, date: today)
    return nil if [current.closing_day, current.due_day] == wanted

    row = card_schedules.find_or_initialize_by(valid_from: schedule_start_on(today))
    row.assign_attributes(closing_day: wanted[0], due_day: wanted[1])
    row
  end

  private

  # O clamp NÃO protege a fronteira de janela — quem garante isso é
  # window_start, que devolve o início da janela aberta por definição. Ele
  # garante só ordenação: uma vigência nova jamais antecede uma já existente.
  # É um backstop contra linhas escritas fora daqui (correção pelo console,
  # migração de dados, spec montando card_schedules na mão), que podem estar
  # em datas que não são fronteira de janela nenhuma.
  def schedule_start_on(today)
    boundary = Budgeting::StatementAttribution.window_start(card: self, date: today)
    # maximum nunca é nil aqui: Schedule.for já teria levantado sem vigência.
    [boundary, card_schedules.maximum(:valid_from)].max
  end
end
