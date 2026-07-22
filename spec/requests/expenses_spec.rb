require "rails_helper"

RSpec.describe "Expenses", type: :request do
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

  it "accepts a debit expense in the credit-card category — fatura payment (AC 11)" do
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

  # Point 3 (project owner's decision): there is no avulso<->parcelado
  # conversion, so unchecking "parcelado" or switching method away from
  # crédito on a purchase edit must be impossible to request, not just
  # ignored server-side.
  describe "locking parcelado/method controls on a purchase edit" do
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

    it "leaves them enabled when editing a plain (avulso) expense" do
      expense = Expense.create!(name: "padaria", amount_cents: 100, payment_method: "cash",
                                category: others, date: Date.new(2026, 3, 10))
      get edit_expense_path(expense)
      doc = Nokogiri::HTML::Document.parse(response.body)

      installment_checkbox = doc.at_css('input[name="expense_entry[installment]"][type="checkbox"]')
      expect(installment_checkbox["disabled"]).to be_nil

      doc.css('input[name="expense_entry[payment_method]"]').each { |radio| expect(radio["disabled"]).to be_nil }
    end

    it "leaves them enabled on the new form" do
      get new_expense_path
      doc = Nokogiri::HTML::Document.parse(response.body)

      installment_checkbox = doc.at_css('input[name="expense_entry[installment]"][type="checkbox"]')
      expect(installment_checkbox["disabled"]).to be_nil

      doc.css('input[name="expense_entry[payment_method]"]').each { |radio| expect(radio["disabled"]).to be_nil }
    end
  end

  # Point 4 (project owner's decision): editing a parcelado destroys and
  # recreates its parcelas, so a stale `/expenses/:id` link (e.g. from an
  # already-open page) now 404s at the AR layer. App-wide rescue instead of
  # an unhandled 500.
  # Fix 1 (task-6 review pass): `ExpensesController` overrides the app-wide
  # `record_not_found` handler with the parcela-aware wording, since it's
  # the only controller where that explanation is actually true. Asserted
  # here alongside `spec/requests/cards_spec.rb`'s "stale card URL" example,
  # which asserts the same rendered text is ABSENT there.
  it "redirects with the parcela-aware alert when the expense id no longer exists (Fix 1)" do
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

  # Fix 3 (task-6 review pass): the rendered edit form disables the parcelado
  # checkbox and the three payment-method radios on a purchase edit (Point 3
  # above) — disabled inputs submit nothing, so a real browser PATCH from
  # that page carries no `payment_method` and no `installment` key at all.
  # Every other example in this file hands both keys to `patch` by hand,
  # which only proves `ExpenseEntry#update`'s CURRENT dispatch (a `case
  # source` on the record's own class) survives; it would stay green even if
  # someone rewrote that dispatch to key on `entry.installment?` instead
  # (`nil.to_s == "1"` is false when the key is simply absent), which would
  # silently skip `update_purchase` — and its series regeneration — for
  # every real parcelado edit. This spec omits both keys the way the
  # disabled browser form actually would, so it catches that regression.
  it "regenerates a parcelado series from a PATCH with payment_method and installment genuinely absent (Fix 3)" do
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
end
