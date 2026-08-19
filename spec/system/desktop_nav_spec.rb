require "rails_helper"

# The desktop chrome: a top nav showing as many destinations inline as fit, the
# rest under a "Mais" dropdown, plus the month navigator (only on month-scoped
# screens) and the theme toggle. The floating "+" lives bottom-right (fab spec).
RSpec.describe "Desktop app shell", type: :system do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  # Labels the nav controller left inline (not folded into the Mais menu).
  def inline_labels
    page.evaluate_script(<<~JS)
      [...document.querySelectorAll('nav [data-nav-target="item"]')]
        .filter((el) => el.closest('[data-nav-target="menu"]') === null)
        .map((el) => el.textContent.trim())
    JS
  end

  def body_fits? = page.evaluate_script("document.body.scrollWidth <= document.body.clientWidth")

  it "shows every destination inline and hides Mais at a wide width (AC1)" do
    page.driver.browser.manage.window.resize_to(1400, 900)
    visit root_path

    expect(inline_labels).to include("Início", "Gastos", "Ganhos", "Cartões", "Categorias", "Análise", "Config")
    expect(page).to have_css('[data-nav-target="more"]', visible: :hidden)
    expect(body_fits?).to be true
  end

  it "folds overflow destinations into a reachable Mais dropdown when narrowed (AC6)" do
    # 600px would trip the shell's own md:768 breakpoint and swap to the mobile
    # bars entirely; 770px stays just inside desktop chrome while still being
    # too narrow for all seven destinations + lockup + month nav + toggle.
    page.driver.browser.manage.window.resize_to(770, 900)
    visit root_path

    expect(page).to have_css('[data-nav-target="more"]', visible: true)
    expect(inline_labels.length).to be < 7

    click_button "Mais ▾"
    within('[data-nav-target="menu"]') { expect(page).to have_link("Config") }
    expect(body_fits?).to be true
  end

  it "hosts the month navigator on a month-scoped screen and omits it on Config" do
    page.driver.browser.manage.window.resize_to(1400, 900)

    visit root_path
    within("nav") { expect(page).to have_content(%r{\d{2}/\d{4}}) }

    visit edit_settings_path
    within("nav") { expect(page).not_to have_content(%r{\d{2}/\d{4}}) }
  end
end
