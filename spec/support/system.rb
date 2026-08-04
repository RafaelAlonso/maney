RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 390, 844 ]
  end
end

# Capybara's own default (2s) is tuned for DOM assertions, not for a Turbo
# visit finishing a fetch and redrawing a Chart.js canvas — a round trip that,
# on a loaded CI box, can outrun 2s even though the app is correct. Raising it
# only slows a spec down when a matcher would otherwise time out for real.
Capybara.default_max_wait_time = 5
