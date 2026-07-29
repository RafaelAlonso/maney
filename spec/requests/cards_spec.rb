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
    expect(response.body).to include("Dia de fechamento deve estar entre 1 e 31")
    expect(response.body).not_to include("Card schedules is invalid")
  end

  # `confirm_days: "1"` from here on: a days change that moves due dates the user
  # already has ahead of them goes through one confirmation screen first (see
  # "the confirmation before a days change" below). These examples are about what
  # gets written, so they answer it up front and go straight to the write.
  it "editing days creates a new schedule valid from today, keeping the old one (AC 16)" do
    card = create_card!(closing_day: 5, due_day: 12)
    patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 27 }, confirm_days: "1" }
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

  # Azul (helper default) closes on day 5, is due on day 12, first validity
  # window on 01/03/2026. On 21/07/2026 the open window is [03/07, 05/08) (see
  # spec/models/card_spec.rb). The first correction adopts closing day 20: under
  # that day, July's statement closes on 20/07 — BEFORE today (21/07) — so the
  # window containing today becomes [20/07, 20/08). The second correction on the
  # same day lands in that new window and so stacks a row instead of amending the
  # 03/07 one: amending would reopen an already-closed statement (20/07). The
  # "amends the same row" behavior (see spec/models/card_spec.rb) stays covered
  # for edits that close no statement between them; we don't duplicate that case here.
  it "editing twice on the same day creates a new validity window when the first already closed a statement" do
    travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
      card = create_card!
      patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 27 }, confirm_days: "1" }
      patch card_path(card), params: { card: { name: "Azul", closing_day: 21, due_day: 27 }, confirm_days: "1" }
      expect(card.card_schedules.count).to eq 3
      expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 21
    end
  end

  # Azul (helper default) closes on day 5, is due on day 12, first validity
  # window on 01/03/2026. On 21/07/2026 the open window is [03/07, 05/08). The
  # first correction adopts closing day 28 — still upcoming within the window —
  # so it closes no statement and creates a new row on 03/07 (see
  # spec/models/card_spec.rb, "two corrections on the same day amend the same
  # row"). The second correction lands in the SAME window and so reuses that
  # already-persisted row — the scenario `Card#reschedule` documents as "can come
  # back persisted" and that `all?(&:valid?)` masks via short-circuit when the
  # name is also invalid.
  it "reports both the name error and the schedule's own error when a persisted schedule row is dirtied together with an invalid name (Fix 2)" do
    travel_to(Time.zone.local(2026, 7, 21, 10, 0, 0)) do
      card = create_card!
      patch card_path(card), params: { card: { name: "Azul", closing_day: 28, due_day: 10 }, confirm_days: "1" }
      expect(response).to redirect_to(cards_path)
      expect(card.card_schedules.reload.count).to eq(2)

      patch card_path(card), params: { card: { name: "", closing_day: 99, due_day: 10 } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Nome não pode ficar em branco")
      expect(response.body).to include("Dia de fechamento deve estar entre 1 e 31")
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
  # carry `ExpensesController`'s installment-specific explanation ("editar uma
  # parcela recalcula a compra inteira...") for every controller, including
  # this one, where it's simply false — a stale card id has nothing to do
  # with installments. Paired with `spec/requests/expenses_spec.rb`'s
  # "installment-aware alert" example, which asserts that same text IS present
  # there.
  it "redirects with a neutral alert (no installment-specific wording) when the card id no longer exists (Fix 1)" do
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

  # The exploratory pass' open question, settled: the engine keeps working the
  # way issuers do — one installment per statement, following the card's own
  # statement chain — and what was missing is that the user couldn't see the
  # consequence coming. Closing and due days are independent here, so changing
  # 5/12 to 20/12 flips `due_day < closing_day` and postpones the whole open
  # chain by a month, dragging every unbilled installment with it. That now
  # takes one confirmation that names the dates.
  describe "the confirmation before a days change" do
    # Azul closes on day 5, is due on day 12. Under 20/12 the August statement
    # closes on the 20th and, with the due day now before the closing day, is due
    # in September — 12/09 (Saturday) → 14/09.
    it "asks before a change that postpones the due dates, and writes nothing yet" do
      travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
        card = create_card!(closing_day: 5, due_day: 12)

        patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 12 } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("12/08/2026").and include("14/09/2026")
        expect(card.card_schedules.reload.count).to eq 1
        expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 5
      end
    end

    it "counts the unbilled installments that travel with the change" do
      travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
        card = create_card!(closing_day: 5, due_day: 12)
        InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                    card:, category: Category.find_by!(role: "others"),
                                    date: Date.new(2026, 3, 10))

        patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 12 } }

        # 1/10 … 4/10 are billed by 28/07; the remaining six still travel.
        expect(response.body).to include("6 parcelas ainda não faturadas acompanham")
      end
    end

    it "writes the change once confirmed" do
      travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
        card = create_card!(closing_day: 5, due_day: 12)

        patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 12 },
                                         confirm_days: "1" }

        expect(response).to redirect_to(cards_path)
        expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 20
      end
    end

    # The confirmation is for a real consequence, not a toll on every edit: a
    # change that leaves the due dates where they are goes straight through.
    it "does not ask when the due dates do not move" do
      travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
        card = create_card!(closing_day: 5, due_day: 12)

        patch card_path(card), params: { card: { name: "Azul", closing_day: 3, due_day: 12 } }

        expect(response).to redirect_to(cards_path)
        expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 3
      end
    end

    it "does not ask when only the name changes" do
      card = create_card!(closing_day: 5, due_day: 12)

      patch card_path(card), params: { card: { name: "Azul Infinite", closing_day: 5, due_day: 12 } }

      expect(response).to redirect_to(cards_path)
      expect(card.reload.name).to eq "Azul Infinite"
    end
  end
end
