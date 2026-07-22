require "rails_helper"

RSpec.describe "Expense entry flow", type: :system do
  before { create_setting!; create_reserved_categories! }

  it "redirects to setup when unconfigured" do
    Setting.instance.destroy!
    visit root_path
    expect(page).to have_content("Primeiro acesso")
  end

  it "launches a debit expense through the FAB (AC 4 + FAB)" do
    visit root_path
    find("button[aria-label='Lançar']").click
    click_link "gasto"
    fill_in "Nome", with: "padaria"
    fill_in "expense_entry[amount]", with: "50,00"
    choose "débito"
    click_button "Salvar"
    expect(page).to have_content("Gasto lançado")
    expect(page).to have_content("padaria")
  end

  it "shows card and installment fields only for credit, and hides the reserved category (AC 11/13)" do
    create_card!(name: "Azul")
    visit new_expense_path
    expect(page).to have_no_select("expense_entry[card_id]")
    choose "crédito"
    expect(page).to have_select("expense_entry[card_id]")
    expect(page).to have_field("parcelado")
    option = find("select[name='expense_entry[category_id]'] option", text: "cartão de crédito", visible: :all)
    expect(option).to be_disabled
    check "parcelado"
    expect(page).to have_field("Nº de parcelas")
    expect(page).to have_content("Valor total")
  end

  it "confirms whole-purchase deletion from an installment row (AC 9)" do
    card = create_card!
    others = Category.find_by!(role: "others")
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))
    visit expenses_path(month: "2026-03")
    accept_confirm(/compra parcelada inteira/) do
      first("li", text: "sofá 1/10").find_button("excluir").click
    end
    expect(page).to have_content("Compra parcelada excluída")
    expect(InstallmentPurchase.count).to eq 0
  end

  # Task 6 fixed a bug in expense_form_controller.js that had zero executable
  # coverage until this system spec existed: when the reserved "cartão de
  # crédito" category option gets disabled+hidden (payment method switched to
  # crédito) while it happens to be the selected one, merely deselecting it
  # (`selected = false`) leaves the <select> with nothing selected, and the
  # browser silently falls back to the first ENABLED option in DOM order —
  # an arbitrary category, not the user's intent. The fix explicitly selects
  # the reserved "outros" option instead.
  #
  # That combination (payment_method=credit + category=cartão de crédito) is
  # not reachable by clicking through this page: the controller's own
  # `refresh()` runs on every `change` of the payment-method radio and
  # disables the reserved option before a user could ever pick it while
  # crédito is selected. The one real way to reach it — per the comment in
  # `expense_form_controller.js` — is the server round-trip: a credit
  # expense filed under that reserved category is rejected server-side
  # (Expense#credit_never_in_credit_card_category), and Rails re-renders
  # `new` with the rejected values still in place (category still selected,
  # crédito radio still checked); `connect()` then calls `refresh()` on that
  # freshly rendered form, which is exactly where the bug lived. We drive
  # the real POST-then-422-render round trip and bypass only the piece a
  # real user CAN'T avoid triggering client-side (the change event on the
  # radio, which pre-empts the invalid combination before it can be
  # submitted) by setting the DOM values directly instead of clicking —
  # everything after that point (the actual POST, the server-side
  # rejection, the re-render, and the Stimulus connect/refresh on the
  # result) is genuine.
  #
  # A plain "alimentação" category is added so the fixture has three
  # non-reserved-adjacent options in DOM order (Category.order(:name):
  # alimentação, cartão de crédito, outros) — without it, "first enabled
  # option in DOM order" and "outros" coincide and the example would pass
  # even with the pre-fix behavior.
  it "selects the reserved 'outros' category after the server rejects a credit expense filed under " \
     "'cartão de crédito' (Task 6 fix, AC 11/13)" do
    Category.create!(name: "alimentação")
    card = create_card!
    credit_card_category = Category.find_by!(role: "credit_card")

    visit new_expense_path
    fill_in "Nome", with: "compra teste"
    fill_in "expense_entry[amount]", with: "10,00"
    fill_in "Data", with: Date.new(2026, 3, 12)

    # Bypass only the client-side `change` handler that a real click would
    # trigger and that would pre-empt this exact combination — see comment
    # above. Everything from `click_button "Salvar"` onward is a genuine
    # round trip through the real server and the real re-rendered page.
    page.execute_script(<<~JS)
      document.querySelector('input[name="expense_entry[payment_method]"][value="credit"]').checked = true
      document.querySelector('select[name="expense_entry[category_id]"]').value = "#{credit_card_category.id}"
      document.querySelector('select[name="expense_entry[card_id]"]').value = "#{card.id}"
    JS
    click_button "Salvar"

    expect(page).to have_content("cartão de crédito não pode ser usada em gastos no crédito")
    expect(page).to have_select("expense_entry[category_id]", selected: "outros")
  end
end
