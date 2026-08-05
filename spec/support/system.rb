RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]
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
