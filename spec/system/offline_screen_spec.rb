require "rails_helper"

# A money app must never render a figure that is no longer current. Rather than
# police that page by page, the service worker stores exactly one thing — a
# static page with no data on it — so there is nothing that *can* go stale.
RSpec.describe "The no-connection screen", type: :system do
  # Only this file talks to the app through the outage forwarder (see
  # spec/support/network_outage.rb), because only here does the network have to
  # go down for real: Chrome's network emulation never reaches a service
  # worker's own `fetch`. `after` hooks run in reverse, so the origin is
  # restored only once the worker below has been unregistered.
  after { restore_direct_network }

  before do
    route_through_network_outage
    create_setting!(initial_balance_cents: 123_45); create_reserved_categories!
  end

  # Capybara reuses one browser across the whole suite, so a worker left
  # registered here would go on intercepting navigations in later examples.
  after do
    go_online
    page.execute_script(<<~JS)
      navigator.serviceWorker.getRegistrations().then((registrations) => {
        registrations.forEach((registration) => registration.unregister())
      })
      caches.keys().then((keys) => keys.forEach((key) => caches.delete(key)))
    JS
  end

  # `clients.claim()` takes control of the already-open page on activation, but
  # that is a race against the assertion — one reload removes it entirely.
  def install_service_worker
    visit root_path
    page.evaluate_async_script("navigator.serviceWorker.ready.then(() => arguments[0]())")
    page.refresh
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until page.evaluate_script("!!navigator.serviceWorker.controller")
    end
  end

  it "replaces the browser's error page when Maney is opened with no connection (AC 4)" do
    install_service_worker
    go_offline

    page.refresh

    expect(page).to have_content("Maney precisa de internet para mostrar os seus números.")
    expect(page).to have_button("Tentar de novo")
  end

  it "shows no amount, total or other figure while offline (AC 6)" do
    install_service_worker
    go_offline

    page.refresh

    expect(page).to have_content("Maney precisa de internet")
    expect(page.text).not_to include("R$")
    expect(page.text).not_to match(/\d{1,3},\d{2}/)
  end

  it "loads the app normally when the connection is back and the person retries (AC 5)" do
    install_service_worker
    go_offline
    page.refresh
    expect(page).to have_button("Tentar de novo")

    go_online
    click_button "Tentar de novo"

    expect(page).to have_link("Gastos")
    expect(page).not_to have_content("Maney precisa de internet")
  end
end
