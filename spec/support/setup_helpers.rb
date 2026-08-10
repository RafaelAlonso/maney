module SetupHelpers
  def create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    Setting.create!(first_month:, initial_balance_cents:)
  end

  def create_reserved_categories!
    [ Category.find_or_create_by!(role: "others") { |c| c.name = "outros" },
     Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" } ]
  end

  # Same card as the reference scenario (ReferenceScenario#create_card), but with
  # the first validity window anchored at the start of the timeline — which is
  # what the cards screen does on registration. Delegates on purpose: two helpers
  # with the same body and different valid_from were already a source of confusion.
  def create_card!(name: "Azul", closing_day: 5, due_day: 12, valid_from: nil)
    create_card(name:, closing_day:, due_day:,
                valid_from: valid_from || Setting.instance&.first_month || Date.new(2026, 3, 1))
  end
end

RSpec.configure { |config| config.include SetupHelpers }
