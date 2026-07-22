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

  it "shows the specific closing-day message instead of the generic association error (Fix 1)" do
    post cards_path, params: { card: { name: "Azul", closing_day: 0, due_day: 12 } }
    expect(response.body).to include("Closing day is not included in the list")
    expect(response.body).not_to include("Card schedules is invalid")
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

  # Azul (helper default) fecha dia 5, vence dia 12, primeira vigência em
  # 01/03/2026. Em 21/07/2026 a janela aberta é [03/07, 05/08). A primeira
  # correção adota o dia de fechamento 28 — ainda por vir dentro da janela —
  # então não fecha fatura nenhuma e cria uma linha nova em 03/07 (ver
  # spec/models/card_spec.rb, "duas correções no mesmo dia amendam a mesma
  # linha"). A segunda correção cai na MESMA janela e por isso reaproveita
  # essa linha já persistida — é o cenário que `Card#reschedule` documenta
  # como "pode vir persistida" e que `all?(&:valid?)` mascara via
  # short-circuit quando o nome também está inválido.
  it "reports both the name error and the schedule's own error when a persisted schedule row is dirtied together with an invalid name (Fix 2)" do
    travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
      card = create_card!
      patch card_path(card), params: { card: { name: "Azul", closing_day: 28, due_day: 10 } }
      expect(response).to redirect_to(cards_path)
      expect(card.card_schedules.reload.count).to eq(2)

      patch card_path(card), params: { card: { name: "", closing_day: 99, due_day: 10 } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Name can&#39;t be blank").or include("Name can't be blank")
      expect(response.body).to include("Closing day is not included in the list")
    end
  end

  it "reports failure via alert when destroy is refused despite passing the guard (Fix 3, latent)" do
    card = create_card!
    allow(Card).to receive(:find).with(card.id.to_s).and_return(card)
    allow(card).to receive(:destroy) do
      card.errors.add(:base, "não pode ser excluído")
      false
    end

    delete card_path(card)

    expect(response).to redirect_to(cards_path)
    follow_redirect!
    expect(response.body).to include("não pode ser excluído")
    expect(Card.exists?(card.id)).to be true
  end

  # Fix 1 (task-6 review pass): the app-wide `record_not_found` rescue used to
  # carry `ExpensesController`'s parcela-specific explanation ("editar uma
  # parcela recalcula a compra inteira...") for every controller, including
  # this one, where it's simply false — a stale card id has nothing to do
  # with installments. Paired with `spec/requests/expenses_spec.rb`'s
  # "parcela-aware alert" example, which asserts that same text IS present
  # there.
  it "redirects with a neutral alert (no parcela-specific wording) when the card id no longer exists (Fix 1)" do
    stale_id = Card.maximum(:id).to_i + 1_000
    get edit_card_path(stale_id)
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("não existe mais")
    expect(response.body).not_to include("editar uma parcela recalcula a compra inteira")
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
