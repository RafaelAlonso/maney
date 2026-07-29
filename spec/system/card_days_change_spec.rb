require "rails_helper"

# The confirmation is a full page returned from a PATCH with a 4xx status, which
# is the one shape Turbo renders in place instead of demanding a redirect — worth
# driving for real, because a wrong status here doesn't fail a request spec: it
# fails in the browser, as Turbo's "Form responses must redirect" error.
RSpec.describe "Changing a card's days", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  it "shows the postponed due dates and only writes them once confirmed" do
    travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
      card = create_card!(closing_day: 5, due_day: 12)
      InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                  card:, category: Category.find_by!(role: "others"),
                                  date: Date.new(2026, 3, 10))

      visit edit_card_path(card)
      fill_in "Dia de fechamento", with: "20"
      click_on "Salvar"

      expect(page).to have_content("Confirmar os novos dias")
      expect(page).to have_content("12/08/2026").and have_content("14/09/2026")
      expect(page).to have_content("6 parcelas ainda não faturadas acompanham")
      expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 5

      click_on "Confirmar mudança"

      expect(page).to have_content("Cartão atualizado.")
      expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 20
    end
  end

  it "leaves the card untouched when the confirmation is abandoned" do
    travel_to(Time.zone.local(2026, 7, 28, 10, 0, 0)) do
      card = create_card!(closing_day: 5, due_day: 12)

      visit edit_card_path(card)
      fill_in "Dia de fechamento", with: "20"
      click_on "Salvar"
      click_on "Cancelar"

      expect(page).to have_content("fecha dia 5 · vence dia 12")
      expect(card.card_schedules.reload.count).to eq 1
    end
  end
end
