module SetupHelpers
  def create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    Setting.create!(first_month:, initial_balance_cents:)
  end

  def create_reserved_categories!
    [Category.find_or_create_by!(role: "others") { |c| c.name = "outros" },
     Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" }]
  end

  # Mesmo cartão do cenário de referência (ReferenceScenario#create_card), mas
  # com a primeira vigência ancorada no início da linha do tempo — é o que a
  # tela de cartões faz ao cadastrar. Delega de propósito: dois helpers com
  # corpo igual e valid_from diferente já foram fonte de confusão.
  def create_card!(name: "Azul", closing_day: 5, due_day: 12, valid_from: nil)
    create_card(name:, closing_day:, due_day:,
                valid_from: valid_from || Setting.instance&.first_month || Date.new(2026, 3, 1))
  end
end

RSpec.configure { |config| config.include SetupHelpers }
