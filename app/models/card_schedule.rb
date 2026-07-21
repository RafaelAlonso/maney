class CardSchedule < ApplicationRecord
  belongs_to :card

  validates :closing_day, :due_day, inclusion: { in: 1..31 }
  validates :valid_from, presence: true, uniqueness: { scope: :card_id }

  # Budgeting::Schedule.for memoiza por (card_id, data); qualquer escrita
  # aqui muda o que essa memória deveria responder, então ela é descartada
  # imediatamente (não em after_commit — os specs criam vigências dentro de
  # uma transação que nunca chega a commitar).
  after_save { Budgeting::Schedule.invalidate(card_id:) }
  after_destroy { Budgeting::Schedule.invalidate(card_id:) }
end
