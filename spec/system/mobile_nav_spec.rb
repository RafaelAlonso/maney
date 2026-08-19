require "rails_helper"

# The mobile chrome: a five-slot bottom tab bar (Início · Gastos · [+] · Análise
# · Cartões) and a slim top-bar "Mais" trigger opening a slide-in panel holding
# the overflow destinations, the theme toggle and the brand. Replaces the old
# scrollable top-strip nav.
RSpec.describe "Mobile app shell", type: :system do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  # Headless Chrome won't size its window below ~500 px, so the phone viewport is
  # only reachable through the device-metrics override.
  def emulate_phone(width: 390)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height: 800, deviceScaleFactor: 1, mobile: true)
  end

  # Capybara's session (and its browser tab) survives across examples and even
  # across spec files; a plain window resize does not override a CDP device
  # metrics override, so without clearing it here the desktop spec would still
  # see this phone viewport if it runs right after this file.
  after { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  it "shows the five-slot bottom bar with the active tab marked" do
    visit root_path
    emulate_phone

    within find("nav", text: "Início") do
      expect(page).to have_link("Início")
      expect(page).to have_link("Gastos")
      expect(page).to have_button("Lançar")
      expect(page).to have_link("Análise")
      expect(page).to have_link("Cartões")
    end
    expect(find_link("Início")["aria-current"]).to eq "page"
  end

  it "opens income/expense entry from the center + carrying the on-screen month" do
    visit expenses_path(month: "2026-05")
    emulate_phone

    find("button[aria-label='Lançar']").click
    expect(page).to have_link("gasto", href: new_expense_path(month: "2026-05"))
    expect(page).to have_link("ganho", href: new_income_path(month: "2026-05"))
  end

  it "reaches Ganhos, Categorias, Config, the theme toggle and the brand through Mais" do
    visit root_path
    emulate_phone

    click_button "Mais"
    expect(page).to have_css("[data-mais-panel-target='scrim']", visible: true)  # panel opened
    within "aside" do
      expect(page).to have_link("Ganhos")
      expect(page).to have_link("Categorias")
      expect(page).to have_link("Config")
      expect(page).to have_button("Tema")
      expect(page).to have_css("img[alt='maney']")
    end

    click_link "Categorias"
    expect(page).to have_current_path(categories_path, ignore_query: true)
  end
end
