module Budgeting
  # Vigência dos dias do cartão em efeito numa data. Editar os dias do
  # cartão = nova linha em card_schedules valendo da janela aberta em
  # diante; faturas fechadas seguem sendo derivadas da vigência antiga.
  #
  # A consulta é sempre refeita: nada aqui é memoizado. Um cache de processo
  # chegou a ser escrito e foi revertido — ele servia vigência velha depois
  # de qualquer escrita que não passasse pelos callbacks do model
  # (update_all, migração de dados, correção pelo console), ou seja, dinheiro
  # errado a partir de código de aparência correta. Se o custo por consulta
  # virar problema quando houver tela, memoize por derivação (um memo
  # passado adiante por StatementSet/MonthSummary), nunca em estado global.
  Schedule = Data.define(:closing_day, :due_day, :valid_from) do
    def self.for(card:, date:)
      row = card.card_schedules.where(valid_from: ..date).order(valid_from: :desc).first ||
            card.card_schedules.order(:valid_from).first
      raise ArgumentError, "card #{card.id} has no schedule" if row.nil?
      new(closing_day: row.closing_day, due_day: row.due_day, valid_from: row.valid_from)
    end
  end
end
