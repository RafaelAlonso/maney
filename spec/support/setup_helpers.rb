module SetupHelpers
  def create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    Setting.create!(first_month:, initial_balance_cents:)
  end

  def create_reserved_categories!
    [Category.find_or_create_by!(role: "others") { |c| c.name = "outros" },
     Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" }]
  end

  def create_card!(name: "Azul", closing_day: 5, due_day: 12, valid_from: Date.new(2026, 3, 1))
    card = Card.create!(name:)
    card.card_schedules.create!(closing_day:, due_day:, valid_from:)
    card
  end
end

RSpec.configure { |config| config.include SetupHelpers }
