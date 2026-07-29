require "rails_helper"

# The language policy (CLAUDE.md) keeps every text a user reads in Portuguese —
# and validation messages reach the user through `errors.full_messages`, which
# prefixes each message with the *humanized attribute name*. With only an en
# locale, that prefix came out in English on every screen, including on top of
# hand-written Portuguese sentences ("Initial balance não é um valor válido",
# "Date anterior ao primeiro mês"). These are the exact messages collected in
# the exploratory pass; each one guards the whole chain (locale file loaded,
# default locale set, attribute name mapped).
RSpec.describe "Validation messages the user reads", type: :request do
  def body = response.body

  it "names the attribute in Portuguese on a card with no name" do
    create_setting!
    create_reserved_categories!

    post cards_path, params: { card: { name: "", closing_day: 5, due_day: 12 } }

    expect(body).to include("Nome não pode ficar em branco")
  end

  # "is not included in the list" told the user nothing about what to type.
  it "says what a valid card day is, instead of 'not included in the list'" do
    create_setting!
    create_reserved_categories!

    post cards_path, params: { card: { name: "Azul", closing_day: 99, due_day: 0 } }

    expect(body).to include("Dia de fechamento deve estar entre 1 e 31")
    expect(body).to include("Dia de vencimento deve estar entre 1 e 31")
  end

  it "names the amount in Portuguese on an income that is not positive" do
    create_setting!
    create_reserved_categories!

    post incomes_path, params: { income: { name: "salário", amount: "0,00", date: "2026-03-01" } }

    expect(body).to include("Valor deve ser maior que 0")
  end

  # The two worst of the pass: a hand-written Portuguese sentence with an
  # English attribute name bolted onto the front.
  it "prefixes the initial-balance message in Portuguese on first access" do
    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "abc" } }

    expect(body).to include("Saldo inicial não é um valor válido")
  end

  it "prefixes the timeline message in Portuguese" do
    create_setting!(first_month: Date.new(2026, 3, 1))
    create_reserved_categories!

    post incomes_path, params: { income: { name: "x", amount: "10,00", date: "2026-02-01" } }

    expect(body).to include("Data anterior ao primeiro mês — a linha do tempo começa em 03/2026")
  end
end
