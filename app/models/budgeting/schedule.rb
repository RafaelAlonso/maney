module Budgeting
  # Vigência dos dias do cartão em efeito numa data. Editar os dias do
  # cartão = nova linha em card_schedules valendo da janela aberta em
  # diante; faturas fechadas seguem sendo derivadas da vigência antiga.
  Schedule = Data.define(:closing_day, :due_day, :valid_from) do
    def self.for(card:, date:)
      row = card.card_schedules.where(valid_from: ..date).order(valid_from: :desc).first ||
            card.card_schedules.order(:valid_from).first
      raise ArgumentError, "card #{card.id} has no schedule" if row.nil?
      new(closing_day: row.closing_day, due_day: row.due_day, valid_from: row.valid_from)
    end
  end
end
