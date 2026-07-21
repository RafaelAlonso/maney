# Cenário de referência das stories: cartão Azul fecha dia 5, vence dia 12,
# ano 2026. Categorias reservadas conforme seeds.
module ReferenceScenario
  def create_card(name: "Azul", closing_day: 5, due_day: 12, valid_from: Date.new(2026, 1, 1))
    card = Card.create!(name:)
    card.card_schedules.create!(closing_day:, due_day:, valid_from:)
    card
  end

  def others_category
    Category.find_or_create_by!(role: "others") { |c| c.name = "outros" }
  end

  def credit_card_category
    Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" }
  end

  def category(name = "mercado")
    Category.find_or_create_by!(name:)
  end
end

RSpec.configure { |config| config.include ReferenceScenario }
