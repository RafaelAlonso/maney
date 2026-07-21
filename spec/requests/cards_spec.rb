require "rails_helper"

RSpec.describe "Cards", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!; create_reserved_categories! }

  it "lists cards with their current days (AC 1)" do
    create_card!(name: "Azul", closing_day: 5, due_day: 12)
    get cards_path
    expect(response.body).to include("Azul").and include("fecha dia 5").and include("vence dia 12")
  end

  it "creates a card with its first schedule from the first month (AC 1)" do
    post cards_path, params: { card: { name: "Azul", closing_day: 5, due_day: 12 } }
    card = Card.find_by!(name: "Azul")
    schedule = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 10))
    expect([schedule.closing_day, schedule.due_day]).to eq [5, 12]
    expect(schedule.valid_from).to eq Setting.instance.first_month
  end

  it "rejects invalid days" do
    post cards_path, params: { card: { name: "Azul", closing_day: 0, due_day: 12 } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "editing days creates a new schedule valid from today, keeping the old one (AC 16)" do
    card = create_card!(closing_day: 5, due_day: 12)
    patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 27 } }
    expect(card.card_schedules.count).to eq 2
    old = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 10))
    current = Budgeting::Schedule.for(card:, date: Date.current)
    expect(old.closing_day).to eq 5
    expect(current.closing_day).to eq 20
  end

  it "editing only the name does not create a schedule" do
    card = create_card!
    patch card_path(card), params: { card: { name: "Azul Infinite", closing_day: 5, due_day: 12 } }
    expect(card.reload.name).to eq "Azul Infinite"
    expect(card.card_schedules.count).to eq 1
  end

  # Azul (helper default) fecha dia 5, vence dia 12, primeira vigência em
  # 01/03/2026. Em 21/07/2026 a janela aberta é [03/07, 05/08) (ver
  # spec/models/card_spec.rb). A primeira correção adota o dia de fechamento
  # 20: sob esse dia, a fatura de julho fecha em 20/07 — ANTES de hoje
  # (21/07) — então a janela que contém hoje passa a ser [20/07, 20/08).
  # A segunda correção do mesmo dia cai nessa janela nova e por isso empilha
  # uma linha em vez de amendar a de 03/07: amendar reabriria uma fatura já
  # fechada (20/07). O comportamento "amenda a mesma linha" (ver
  # spec/models/card_spec.rb) continua coberto para edições que não fecham
  # fatura nenhuma entre si; não duplicamos esse caso aqui.
  it "editar duas vezes no mesmo dia cria vigência nova quando a primeira já fechou uma fatura" do
    travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
      card = create_card!
      patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 27 } }
      patch card_path(card), params: { card: { name: "Azul", closing_day: 21, due_day: 27 } }
      expect(card.card_schedules.count).to eq 3
      expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 21
    end
  end

  it "destroys a card without expenses" do
    card = create_card!
    delete card_path(card)
    expect(Card.exists?(card.id)).to be false
  end

  it "redirects to the migration flow when the card has expenses (AC 17)" do
    card = create_card!
    Expense.create!(name: "mercado", amount_cents: 100, payment_method: "credit",
                    card:, category: Category.find_by!(role: "others"), date: Date.new(2026, 3, 4))
    delete card_path(card)
    expect(response).to redirect_to(new_card_migration_path(card))
    expect(Card.exists?(card.id)).to be true
  end
end
