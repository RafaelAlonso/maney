# CDP + computed-color helpers for the theming spec (Task 3, AC1–3). Mirrors
# how spec/support/authentication.rb includes AuthenticationHelpers — bare
# top-level `def`s in a support file are not in example scope.
module ThemingHelpers
  def set_prefers_color_scheme(scheme)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "prefers-color-scheme", value: scheme.to_s } ])
  end

  def background_of(selector) = evaluate_script("getComputedStyle(document.querySelector('#{selector}')).backgroundColor")

  def rgb(hex)
    r, g, b = hex.delete_prefix("#").scan(/../).map { |p| p.to_i(16) }
    "rgb(#{r}, #{g}, #{b})"
  end
end

RSpec.configure do |config|
  config.include ThemingHelpers, type: :system

  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1024, 768 ]
    # Signing in has to follow `driven_by` — there is no browser before it. The
    # app's own `before` blocks have not run yet, so this lands on /setup; every
    # system spec then `visit`s the page it is actually about.
    authenticate_browser
  end
end

# Signing in now makes every system spec start with a real Turbo round trip
# (the form POST in `authenticate_browser`, then its redirect), on top of
# whatever async work the example itself waits on. Capybara's own default
# (2s) was already tight for a Turbo visit finishing a fetch and redrawing a
# Chart.js canvas (see analysis_spec's page-specific `using_wait_time`); with
# that extra round trip ahead of every example, matchers across otherwise
# unrelated spec files started timing out on a loaded box even though the app
# was correct. Raising it here only slows a spec down when a matcher would
# otherwise time out for real.
Capybara.default_max_wait_time = 5

# `click_link` returns as soon as the click is dispatched, but a Turbo Drive
# visit fetches the page first and only writes its history entry once that
# response renders — a couple of hundred milliseconds later on a busy machine.
# Driving the browser's history inside that window steps back past the page the
# visit started from (in a fresh tab, all the way to `about:blank`) and the
# example never recovers, because the entry it meant to leave behind did not
# exist yet.
#
# So `page.go_back` / `page.go_forward` wait for Turbo to have no visit in
# flight, the same way every other Capybara call waits for the page to settle.
#
# The price: this monkey-patches a third-party class (`Capybara::Session`) and
# reads Turbo internals (`Turbo.session.navigator.currentVisit`) that carry no
# compatibility promise, so a Turbo or Capybara upgrade can break it here.
module SettledTurboBeforeHistoryNavigation
  # A visit is one request plus one render, so it normally settles in a couple
  # of hundred milliseconds; the budget only has to be long enough to survive a
  # loaded machine, where Capybara's own two seconds are not always enough.
  SETTLE_TIMEOUT = 10

  def go_back
    wait_for_turbo
    super
  end

  def go_forward
    wait_for_turbo
    super
  end

  private

  def wait_for_turbo
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SETTLE_TIMEOUT
    sleep 0.01 until turbo_settled? || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  # A page Turbo does not drive — the offline screen, `about:blank`, a browser
  # error page — has nothing to wait for.
  def turbo_settled?
    evaluate_script(<<~JS)
      !(window.Turbo && (Turbo.session.navigator.currentVisit || Turbo.session.navigator.formSubmission))
    JS
  rescue StandardError
    true
  end
end

Capybara::Session.prepend(SettledTurboBeforeHistoryNavigation)
