module Budgeting
  # Vigência dos dias do cartão em efeito numa data. Editar os dias do
  # cartão = nova linha em card_schedules valendo da janela aberta em
  # diante; faturas fechadas seguem sendo derivadas da vigência antiga.
  Schedule = Data.define(:closing_day, :due_day, :valid_from) do
    # Cache por (card_id, date): evita repetir a consulta a cada passo de
    # `succ` (uma compra de N parcelas faz N lookups do mesmo cartão).
    # CardSchedule invalida as entradas do cartão a cada escrita, então o
    # cache nunca sobrevive a uma mudança de vigência — inclusive dentro do
    # mesmo teste, que cria vigências no meio do exemplo.
    CACHE = {}
    MUTEX = Mutex.new

    def self.for(card:, date:)
      key = [card.id, date]
      MUTEX.synchronize { CACHE.fetch(key) { CACHE[key] = build(card:, date:) } }
    end

    def self.invalidate(card_id:)
      MUTEX.synchronize { CACHE.reject! { |(cached_card_id, _date), _schedule| cached_card_id == card_id } }
    end

    def self.build(card:, date:)
      row = card.card_schedules.where(valid_from: ..date).order(valid_from: :desc).first ||
            card.card_schedules.order(:valid_from).first
      raise ArgumentError, "card #{card.id} has no schedule" if row.nil?
      new(closing_day: row.closing_day, due_day: row.due_day, valid_from: row.valid_from)
    end
  end
end
