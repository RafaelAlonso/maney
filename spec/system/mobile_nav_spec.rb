require "rails_helper"

# Configurações is the only route to the alert threshold, the initial balance,
# the first month and renaming the reserved categories. The top nav is a single
# flex row, and flex items shrink below their content by default — so on a
# 360 px phone (Pixel / Galaxy S class) the row silently squeezed its last items
# instead of overflowing: "Categorias" clipped, "Config" rendered as "Co", and
# with scrollWidth === clientWidth there was no gesture that reached them.
RSpec.describe "Top navigation on a small phone", type: :system do
  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  # Not `driven_by(screen_size:)`: headless Chrome refuses to make its window
  # narrower than ~500 px, so the viewport the assertions need can only be had
  # through the device-metrics override.
  def emulate_phone(width:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
                                    width:, height: 800, deviceScaleFactor: 1, mobile: true)
  end

  it "keeps Config reachable by scrolling the nav instead of clipping it" do
    visit root_path
    emulate_phone(width: 360)

    nav = page.evaluate_script(<<~JS)
      (() => {
        const nav = document.querySelector("nav");
        const config = [...nav.querySelectorAll("a")].find(a => a.textContent.trim() === "Config");
        return {
          scrollable: nav.scrollWidth > nav.clientWidth,
          configWidth: config.getBoundingClientRect().width,
          bodyOverflows: document.body.scrollWidth > document.body.clientWidth
        };
      })()
    JS

    # The nav overflows and scrolls, so every item is reachable...
    expect(nav["scrollable"]).to be true
    # ...at its full width, rather than squeezed down to "Co"...
    expect(nav["configWidth"]).to be > 40
    # ...without dragging the whole page sideways.
    expect(nav["bodyOverflows"]).to be false
  end
end
