require "rails_helper"

RSpec.describe "Expenses", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }
  let(:credit_card_cat) { Category.find_by!(role: "credit_card") }
  let(:card) { create_card! }

  it "lists the month's expenses with method label (AC 4)" do
    Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "debit",
                    category: others, date: Date.new(2026, 3, 10))
    get expenses_path(month: "2026-03")
    expect(response.body).to include("padaria").and include("débito")
  end

  it "creates a debit expense (AC 4)" do
    post expenses_path, params: { expense_entry: { name: "padaria", amount: "50,00", date: "2026-03-10",
                                                   category_id: others.id, payment_method: "debit" } }
    expect(Expense.find_by(name: "padaria").payment_method).to eq "debit"
  end

  it "accepts a debit expense in the credit-card category — statement payment (AC 11)" do
    post expenses_path, params: { expense_entry: { name: "fatura azul", amount: "800,00", date: "2026-03-12",
                                                   category_id: credit_card_cat.id, payment_method: "debit" } }
    expect(Expense.find_by(name: "fatura azul").category).to eq credit_card_cat
  end

  it "rejects a credit expense in the credit-card category (AC 11, server side)" do
    post expenses_path, params: { expense_entry: { name: "x", amount: "10,00", date: "2026-03-12",
                                                   category_id: credit_card_cat.id,
                                                   payment_method: "credit", card_id: card.id } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "shows the register-a-card message on the form when there is no card (AC 13)" do
    get new_expense_path
    expect(response.body).to include("cadastre um cartão").and include(new_card_path)
  end

  it "creates an installment purchase from the same form (AC 6)" do
    post expenses_path, params: { expense_entry: { name: "sofá", amount: "1.000,00", date: "2026-03-10",
                                                   category_id: others.id, payment_method: "credit",
                                                   card_id: card.id, installment: "1", installments_count: "10" } }
    expect(InstallmentPurchase.find_by(name: "sofá").expenses.count).to eq 10
  end

  # Fix 1 (final review pass): `installment?` used to dispatch `save` on its
  # own, and `build_purchase` never read `payment_method` — so a submission
  # that started as credit (card chosen, installment checked) and was then
  # switched to debit/cash before Save stored a real InstallmentPurchase
  # anyway. Since `Budgeting::BalanceChain.current_balance` only sums
  # `payment_method: %w[debit cash]`, that expense vanished from the balance
  # chain entirely behind a successful "Gasto lançado." — permanently
  # inflating every later month's carried balance. Reject the conflict
  # instead of silently downgrading to standalone or upgrading the method to
  # credit; both would discard what the user actually typed.
  describe "installment requires credit (Fix 1)" do
    it "rejects debit + installment, creating no InstallmentPurchase" do
      expect do
        post expenses_path, params: { expense_entry: { name: "sofá", amount: "1.200,00", date: "2026-03-10",
                                                        category_id: others.id, payment_method: "debit",
                                                        card_id: card.id, installment: "1",
                                                        installments_count: "12" } }
      end.not_to change(InstallmentPurchase, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("só se aplica a gastos no crédito")
    end

    # This is the reported related symptom: cash + installment + no card
    # used to 422 with "Card must exist" — an English message about a field
    # (`card_id`) this form never shows for cash. The real conflict
    # (installment without credit) must be the one reported, not a downstream
    # validation on a record that should never have been built.
    it "rejects cash + installment, creating no InstallmentPurchase, without naming the card column" do
      expect do
        post expenses_path, params: { expense_entry: { name: "sofá", amount: "1.200,00", date: "2026-03-10",
                                                        category_id: others.id, payment_method: "cash",
                                                        installment: "1", installments_count: "12" } }
      end.not_to change(InstallmentPurchase, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("só se aplica a gastos no crédito")
      expect(response.body).not_to include("Card must exist")
    end

    it "still accepts credit + installment (regression guard)" do
      expect do
        post expenses_path, params: { expense_entry: { name: "sofá", amount: "1.200,00", date: "2026-03-10",
                                                        category_id: others.id, payment_method: "credit",
                                                        card_id: card.id, installment: "1",
                                                        installments_count: "12" } }
      end.to change(InstallmentPurchase, :count).by(1)
      expect(response).to redirect_to(expenses_path(month: "2026-03"))
    end
  end

  it "rejects invalid amounts with a message (AC 14)" do
    post expenses_path, params: { expense_entry: { name: "x", amount: "0,00", date: "2026-03-10",
                                                   category_id: others.id, payment_method: "cash" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
  end

  it "blocks dates before the first month (AC 19)" do
    post expenses_path, params: { expense_entry: { name: "x", amount: "10,00", date: "2026-02-10",
                                                   category_id: others.id, payment_method: "cash" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("primeiro mês")
  end

  it "moving a credit expense's date moves its statement (AC 10)" do
    expense = Expense.create!(name: "mercado", amount_cents: 20_000, payment_method: "credit",
                              card:, category: others, date: Date.new(2026, 3, 4))
    patch expense_path(expense), params: { expense_entry: { name: "mercado", amount: "200,00", date: "2026-03-06",
                                                            category_id: others.id, payment_method: "credit",
                                                            card_id: card.id } }
    expect(Budgeting::StatementSet.statement_of(expense.reload).effective_due).to eq Date.new(2026, 4, 13)
  end

  it "editing any installment edits the whole purchase (AC 9)" do
    purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                           card:, category: others, date: Date.new(2026, 3, 10))
    third = purchase.expenses.find_by!(installment_number: 3)
    get edit_expense_path(third)
    expect(response.body).to include("1.000,00")

    patch expense_path(third), params: { expense_entry: { name: "sofá", amount: "500,00", date: "2026-03-10",
                                                          category_id: others.id, payment_method: "credit",
                                                          card_id: card.id, installment: "1",
                                                          installments_count: "5" } }
    expect(purchase.reload.expenses.count).to eq 5
  end

  it "deleting any installment deletes the whole purchase (AC 9)" do
    purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                           card:, category: others, date: Date.new(2026, 3, 10))
    delete expense_path(purchase.expenses.first)
    expect(InstallmentPurchase.exists?(purchase.id)).to be false
    expect(Expense.where(name: "sofá 1/10")).to be_empty
  end

  it "deletes a plain expense" do
    expense = Expense.create!(name: "padaria", amount_cents: 100, payment_method: "cash",
                              category: others, date: Date.new(2026, 3, 10))
    delete expense_path(expense)
    expect(Expense.exists?(expense.id)).to be false
  end

  # --- Deviations from the brief (see task-6 orchestrator message) ---

  # Point 1: `entry` (ExpenseEntry) is never `persisted?`, so a bare
  # `form_with model: entry, url: url` always infers POST — including on the
  # edit page, where the collection route only defines PATCH/PUT. This test
  # drives the form exactly as rendered (its own action + verb), so if the
  # partial ever regresses to inferring POST, this fails with a routing
  # error instead of silently passing like a hand-written `patch` would.
  it "submits the edit form with its own rendered action and verb (regression guard for POST-vs-PATCH)" do
    expense = Expense.create!(name: "padaria", amount_cents: 100, payment_method: "cash",
                              category: others, date: Date.new(2026, 3, 10))
    get edit_expense_path(expense)
    doc = Nokogiri::HTML::Document.parse(response.body)
    form = doc.at_css("form")
    action = form["action"]
    verb = form.at_css('input[name="_method"]')&.[]("value") || "post"

    send(verb.downcase.to_sym, action, params: { expense_entry: { name: "padaria atualizada", amount: "1,00",
                                                                   date: "2026-03-10", category_id: others.id,
                                                                   payment_method: "cash" } })

    expect(response).to redirect_to(expenses_path(month: "2026-03"))
    expect(Expense.find(expense.id).name).to eq "padaria atualizada"
  end

  # Point 3 (project owner's decision): there is no standalone<->installment
  # conversion, so unchecking the installment box or switching method away from
  # credit on a purchase edit must be impossible to request, not just
  # ignored server-side.
  describe "locking installment/method controls on a purchase edit" do
    it "disables them when editing an existing installment purchase" do
      purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                             card:, category: others, date: Date.new(2026, 3, 10))
      get edit_expense_path(purchase.expenses.first)
      doc = Nokogiri::HTML::Document.parse(response.body)

      installment_checkbox = doc.at_css('input[name="expense_entry[installment]"][type="checkbox"]')
      expect(installment_checkbox["disabled"]).to eq "disabled"

      method_radios = doc.css('input[name="expense_entry[payment_method]"]')
      expect(method_radios).not_to be_empty
      method_radios.each { |radio| expect(radio["disabled"]).to eq "disabled" }

      expect(response.body).to include("exclua a compra e lance de novo")
    end

    # Fix 2 (final review): the mirror direction. The project owner ruled
    # that standalone<->installment conversion is impossible in either direction —
    # so the installment checkbox must be locked on a standalone edit too, not
    # just on a purchase edit. This used to assert the opposite (the broken
    # affordance: checkbox enabled, offered, accepted, and silently
    # discarded by `ExpenseEntry#update`'s `case source` dispatch). The
    # payment-method radios stay enabled here on purpose: unlike an installment's
    # method (hardcoded "credit", never read by `update_purchase`), a
    # standalone's `payment_method` is genuinely read and persisted by
    # `ExpenseEntry#update` — locking those radios too would make a real
    # browser submit no `payment_method` at all (disabled inputs don't
    # submit), breaking ordinary standalone edits.
    it "locks the installment checkbox (but not the payment-method radios) when editing a plain (standalone) expense" do
      expense = Expense.create!(name: "padaria", amount_cents: 100, payment_method: "cash",
                                category: others, date: Date.new(2026, 3, 10))
      get edit_expense_path(expense)
      doc = Nokogiri::HTML::Document.parse(response.body)

      installment_checkbox = doc.at_css('input[name="expense_entry[installment]"][type="checkbox"]')
      expect(installment_checkbox["disabled"]).to eq "disabled"

      doc.css('input[name="expense_entry[payment_method]"]').each { |radio| expect(radio["disabled"]).to be_nil }

      expect(response.body).to include("Este gasto é avulso")
      expect(response.body).to include("exclua este gasto e lance de novo marcando")
    end

    it "leaves them enabled on the new form" do
      get new_expense_path
      doc = Nokogiri::HTML::Document.parse(response.body)

      installment_checkbox = doc.at_css('input[name="expense_entry[installment]"][type="checkbox"]')
      expect(installment_checkbox["disabled"]).to be_nil

      doc.css('input[name="expense_entry[payment_method]"]').each { |radio| expect(radio["disabled"]).to be_nil }
    end
  end

  # Point 4 (project owner's decision): editing an installment purchase destroys
  # and recreates its installments, so a stale `/expenses/:id` link (e.g. from an
  # already-open page) now 404s at the AR layer. App-wide rescue instead of
  # an unhandled 500.
  # Fix 1 (task-6 review pass): `ExpensesController` overrides the app-wide
  # `record_not_found` handler with the installment-aware wording, since it's
  # the only controller where that explanation is actually true. Asserted
  # here alongside `spec/requests/cards_spec.rb`'s "stale card URL" example,
  # which asserts the same rendered text is ABSENT there.
  it "redirects with the installment-aware alert when the expense id no longer exists (Fix 1)" do
    stale_id = Expense.maximum(:id).to_i + 1_000
    get edit_expense_path(stale_id)
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("não existe mais")
    expect(response.body).to include("editar uma parcela recalcula a compra inteira")
  end

  # Point 5: `month_of` must read the competence of the specific installment
  # being edited, not the purchase header's own `date` (which only matches
  # the installment numbered `first_installment`). Purchase created
  # 2026-03-10, first_installment defaults to 1, so installment #3's
  # competence is 2026-03 + 2 = 2026-05 — shrinking the series to 5
  # installments (keeping the date the same) still contains #3, so the fixed
  # redirect must land on 2026-05, not on the purchase's own 2026-03.
  it "redirects to the edited installment's own competence month after a purchase edit (AC 9 corollary)" do
    purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                           card:, category: others, date: Date.new(2026, 3, 10))
    third = purchase.expenses.find_by!(installment_number: 3)

    patch expense_path(third), params: { expense_entry: { name: "sofá", amount: "500,00", date: "2026-03-10",
                                                          category_id: others.id, payment_method: "credit",
                                                          card_id: card.id, installment: "1",
                                                          installments_count: "5" } }

    expect(response).to redirect_to(expenses_path(month: "2026-05"))
  end

  # Fix 3 (task-6 review pass): the rendered edit form disables the installment
  # checkbox and the three payment-method radios on a purchase edit (Point 3
  # above) — disabled inputs submit nothing, so a real browser PATCH from
  # that page carries no `payment_method` and no `installment` key at all.
  # Every other example in this file hands both keys to `patch` by hand,
  # which only proves `ExpenseEntry#update`'s CURRENT dispatch (a `case
  # source` on the record's own class) survives; it would stay green even if
  # someone rewrote that dispatch to key on `entry.installment?` instead
  # (`nil.to_s == "1"` is false when the key is simply absent), which would
  # silently skip `update_purchase` — and its series regeneration — for
  # every real installment edit. This spec omits both keys the way the
  # disabled browser form actually would, so it catches that regression.
  it "regenerates an installment series from a PATCH with payment_method and installment genuinely absent (Fix 3)" do
    purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                           card:, category: others, date: Date.new(2026, 3, 10))

    patch expense_path(purchase.expenses.first), params: { expense_entry: {
      name: "sofá", amount: "500,00", date: "2026-03-10",
      category_id: others.id, card_id: card.id, installments_count: "5"
    } }

    expect(response).to redirect_to(expenses_path(month: "2026-03"))
    purchase.reload
    expect(purchase.expenses.count).to eq 5
    expect(purchase.expenses.sum(:amount_cents)).to eq 50_000
    expect(purchase.expenses.pluck(:payment_method).uniq).to eq ["credit"]
    expect(purchase.category).to eq others
    expect(purchase.card).to eq card
  end

  it "labels each credit expense with its statement, linked to the statement (AC 3)" do
    travel_to(Time.zone.local(2026, 3, 20, 10, 0, 0)) do
      Expense.create!(name: "mercado", amount_cents: 20_000, payment_method: "credit",
                      category: others, card:, date: Date.new(2026, 3, 6))

      get expenses_path(month: "2026-03")

      expect(response.body).to include("vence 13/04")
      expect(response.body).to include(card_statement_path(card, "2026-04-05"))
    end
  end

  it "shows no statement label on expenses that are not on credit (AC 3)" do
    travel_to(Time.zone.local(2026, 3, 20, 10, 0, 0)) do
      Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "cash",
                      category: others, date: Date.new(2026, 3, 6))

      get expenses_path(month: "2026-03")

      expect(response.body).to include("padaria")
      expect(response.body).not_to include("vence")
    end
  end

  # The <select> has no blank option, so the browser pre-selects the first option
  # in DOM order — and the list is ordered by name, which put "cartão de crédito"
  # (the reserved statement-payment category) first. Saving without touching the
  # field filed the expense as a statement payment, silently. AC 12 says an
  # expense saved without choosing a category lands in "outros"; the form must
  # pre-select the same category the server falls back to.
  describe "the Categoria field's default (AC 12)" do
    def selected_category_id
      Nokogiri::HTML(response.body)
        .at("select[name='expense_entry[category_id]'] option[selected]")
        &.attr("value")
    end

    it "pre-selects outros on a new expense, not the reserved credit-card category" do
      get new_expense_path

      expect(selected_category_id).to eq(others.id.to_s)
      expect(selected_category_id).not_to eq(credit_card_cat.id.to_s)
    end

    it "keeps the chosen category pre-selected when editing" do
      mercado = Category.create!(name: "mercado")
      expense = Expense.create!(name: "feira", amount_cents: 5_000, payment_method: "cash",
                                category: mercado, date: Date.new(2026, 3, 10))

      get edit_expense_path(expense)

      expect(selected_category_id).to eq(mercado.id.to_s)
    end
  end

  describe "the month in context" do
    # Working in a month that is not the current one is the whole point of
    # "closing the month" — the app must not keep throwing the user back to today.
    it "starts a new expense on the 1st of the month being viewed" do
      travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
        get new_expense_path(month: "2026-03")

        expect(response.body).to include('value="2026-03-01"')
      end
    end

    it "starts a new expense on today when the month being viewed is the current one" do
      travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
        get new_expense_path(month: "2026-07")

        expect(response.body).to include('value="2026-07-28"')
      end
    end

    it "returns to the month the list was showing after a delete" do
      expense = Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "cash",
                                category: others, date: Date.new(2026, 3, 10))

      delete expense_path(expense, month: "2026-03")

      expect(response).to redirect_to(expenses_path(month: "2026-03"))
    end

    it "returns to the month the list was showing after deleting an installment series" do
      purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                             card:, category: others, date: Date.new(2026, 3, 10))

      delete expense_path(purchase.expenses.order(:installment_number).last, month: "2026-12")

      expect(response).to redirect_to(expenses_path(month: "2026-12"))
    end
  end
end
