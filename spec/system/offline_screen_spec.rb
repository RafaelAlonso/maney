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
  #
  # The guard matters on a red run: when an example fails the browser may be
  # sitting on Chrome's own error page, which has no `navigator.serviceWorker`,
  # and an unguarded script would raise here — hiding the real failure behind a
  # cleanup error and leaving the worker registered for the next example.
  after do
    go_online
    page.execute_script(<<~JS)
      if (navigator.serviceWorker) {
        navigator.serviceWorker.getRegistrations().then((registrations) => {
          registrations.forEach((registration) => registration.unregister())
        })
        caches.keys().then((keys) => keys.forEach((key) => caches.delete(key)))
      }
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

  it "shows the no-connection screen when the connection drops mid-navigation" do
    install_service_worker
    go_offline

    click_link "Gastos"

    expect(page).to have_content("Maney precisa de internet para mostrar os seus números.")
  end

  it "does not restore a cached page of figures when going back offline" do
    install_service_worker
    click_link "Gastos"
    expect(page).to have_current_path(expenses_path)
    go_offline

    page.go_back

    expect(page).to have_content("Maney precisa de internet")
    expect(page.text).not_to match(/\d{1,3},\d{2}/)
  end

  # The two examples above go back through Turbo, which makes a real request and
  # so never exercises the bfcache guard in app/javascript/pwa.js. This one does:
  # a full-document `visit` leaves an entry in the browser's back-forward cache,
  # and restoring it renders a whole page of figures with no request for the
  # service worker to intercept.
  #
  # `navigator.onLine` stays true for the whole example — the outage is at the
  # socket, not the link layer, which is the shape of a captive-portal wifi, a
  # network that needs a VPN, or a self-hosted server that is simply down. A
  # guard conditioned on `navigator.onLine` would let the stale page through.
  it "does not restore a bfcached page of figures when the server is unreachable but the phone is online" do
    install_service_worker
    visit expenses_path
    expect(page).to have_current_path(expenses_path)
    go_offline
    expect(page.evaluate_script("navigator.onLine")).to be true

    page.go_back

    expect(page).to have_content("Maney precisa de internet")
    expect(page.text).not_to match(/\d{1,3},\d{2}/)
  end

  it "does not restore a cached page of figures when going forward offline" do
    install_service_worker
    click_link "Gastos"
    page.go_back
    expect(page).to have_link("Gastos")
    go_offline

    page.go_forward

    expect(page).to have_content("Maney precisa de internet")
    expect(page.text).not_to match(/\d{1,3},\d{2}/)
  end
end
