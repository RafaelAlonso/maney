require "rails_helper"

RSpec.describe "Analysis", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }

  def seed_year
    Income.create!(name: "salário", amount_cents: 100_000, date: Date.new(2026, 3, 5))
    Expense.create!(name: "feira", amount_cents: 30_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 6))
  end

  # Every example keeps `visit` AND its assertions inside `travel_to`: the server
  # runs in this process, so letting the block close before a request lands would
  # have Rails answer it with the real current date.

  it "renders the four charts of the year (AC 2, 3, 6, 8)" do
    seed_year
    travel_to(Date.new(2026, 7, 1)) do
      visit analysis_path

      expect(page).to have_css("canvas", count: 4)
      expect(page).to have_content("Gastos por mês")
      expect(page).to have_content("Gastos por categoria")
      expect(page).to have_content("Lucro por mês")
      expect(page).to have_content("Gastos e saídas")

      # A <canvas> tag renders identically from server-rendered ERB whether
      # Chart.js actually drew into it or threw on import — the assertions
      # above cannot see a JS failure. Chart.getChart(canvas) returns the
      # live instance (or undefined), so this is the only check in the file
      # that would fail if a chart's config was malformed or its import 404s.
      expect(page.evaluate_script(<<~JS)).to eq 4
        Array.from(document.querySelectorAll('canvas'))
             .filter(c => window.Chart.getChart(c)).length
      JS
    end
  end

  # A fetch/XHR's PerformanceResourceTiming entry is recorded asynchronously
  # (on response, not on call), so checking immediately after the click races
  # it. Poll briefly for a change instead of trusting a single synchronous
  # read; if nothing shows up before the deadline, none happened.
  def resource_hits_for_analysis
    page.evaluate_script(<<~JS)
      performance.getEntriesByType('resource').filter(e => e.name.includes('/analysis')).length
    JS
  end

  def resource_hits_for_analysis_settling(from:, timeout: 2)
    # Monotonic clock, not Time.now: this runs inside travel_to, which stubs
    # Time.now, so a wall-clock deadline computed from it would never expire
    # and this loop would hang forever.
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      count = resource_hits_for_analysis
      return count if count != from || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.05
    end
  end

  it "switches the profit chart's mode without reloading the page (AC 6)" do
    seed_year
    travel_to(Date.new(2026, 7, 1)) do
      visit analysis_path

      # Resets only on a real document navigation/reload — Turbo Drive never
      # creates one, so this alone would miss a Turbo-intercepted request. It
      # is the top-level-navigation half of the check; resource timing below
      # covers the same-document half.
      before_origin = page.evaluate_script("performance.timeOrigin")
      before_hits = resource_hits_for_analysis

      click_button "Ganhos − saídas"

      after_hits = resource_hits_for_analysis_settling(from: before_hits)

      expect(find_button("Ganhos − saídas")["aria-pressed"]).to eq "true"
      # Neither a full page reload (timeOrigin) nor a same-document request to
      # /analysis (resource timing, which is how Turbo would issue its GET)
      # happened — a single flag on `window` cannot tell the two apart from a
      # Turbo visit, because Turbo never creates a new `window`.
      expect(page.evaluate_script("performance.timeOrigin")).to eq(before_origin)
      expect(after_hits).to eq(before_hits)
    end
  end

  it "reaches another year through the picker (AC 1)" do
    seed_year
    travel_to(Date.new(2027, 5, 10)) do
      visit analysis_path
      expect(page).to have_content("Nenhum lançamento em 2027")

      select "2026", from: "year"

      expect(page).to have_content("Gastos por mês")
    end
  end

  it "shows a message instead of empty axes for a year with no entries (AC 11)" do
    travel_to(Date.new(2026, 7, 1)) do
      visit analysis_path

      expect(page).to have_content("Nenhum lançamento em 2026")
      expect(page).to have_no_css("canvas")
    end
  end

  # Reads a month's bar out of the live Chart.js instance rather than the DOM:
  # a <canvas> renders identically whether Chart.js drew into it or threw, and
  # the first canvas on the page is always "Gastos por mês".
  def bar_at(index)
    page.evaluate_script(<<~JS)
      window.Chart.getChart(document.querySelector('canvas')).data.datasets[0].data[#{index}]
    JS
  end

  def february_bar = bar_at(1)
  def march_bar = bar_at(2)

  it "filters by card and keeps the card when the year changes (AC 2, 6, 7)" do
    azul = create_card!(name: "Azul")
    preto = create_card!(name: "Preto")
    Expense.create!(name: "tv", amount_cents: 100_000, payment_method: "credit",
                    category: mercado, card: azul, date: Date.new(2026, 3, 4))
    Expense.create!(name: "fone", amount_cents: 40_000, payment_method: "credit",
                    category: mercado, card: preto, date: Date.new(2026, 3, 5))
    Expense.create!(name: "tênis", amount_cents: 70_000, payment_method: "credit",
                    category: mercado, card: azul, date: Date.new(2027, 2, 4))

    # Capybara's own default wait (2s) is tuned for DOM assertions, not for a
    # Turbo visit finishing a fetch and redrawing a Chart.js canvas — a round
    # trip that this page's two `select`s below trigger and that can outrun
    # 2s on a loaded box even though the app is correct. Scoped to this
    # example only, so it does not soften a real timeout anywhere else.
    Capybara.using_wait_time(5) do
      travel_to(Date.new(2027, 5, 10)) do
        visit analysis_path(year: 2026)

        # March's bar, straight off the live Chart.js instance: R$ 1.400 for
        # both cards together.
        expect(march_bar).to eq 1_400.0

        select "Azul", from: "card_id"
        # `march_bar` is a raw JS read with no Capybara retry of its own, and
        # the card select's `change` submits an async Turbo visit — reading
        # right after `select` can catch the old chart still mounted. This
        # guard is a Capybara matcher, so it polls until the select (and,
        # with it, the redrawn chart) has actually landed.
        expect(page).to have_select("card_id", selected: "Azul")
        expect(march_bar).to eq 1_000.0

        # The year select still holds 2026 — one form, so the card submit carried it.
        expect(page).to have_select("year", selected: "2026")

        select "2027", from: "year"

        # The card_id guard above reads the same "Azul" before and after this
        # visit lands, so it cannot detect whether the year change has
        # actually arrived — wait on the field that this action changes
        # instead.
        expect(page).to have_select("year", selected: "2027")
        expect(page).to have_select("card_id", selected: "Azul")
        expect(february_bar).to eq 700.0

        select "Todos os cartões", from: "card_id"
        expect(page).to have_select("year", selected: "2027")
      end
    end
  end

  it "shows an empty state, not a blank chart, for a card with no spending (AC 8)" do
    create_card!(name: "Azul")
    seed_year

    # See the comment in the example above: the card select's Turbo visit can
    # outrun Capybara's 2s default even though the app is correct.
    Capybara.using_wait_time(5) do
      travel_to(Date.new(2026, 7, 1)) do
        visit analysis_path

        select "Azul", from: "card_id"

        expect(page).to have_content("Nenhum gasto em Azul em 2026.")
        expect(page).to have_content("Cobre todos os cartões")
        # Profit and "Gastos e saídas" keep their canvases; the two spending
        # charts lost theirs.
        expect(page).to have_css("canvas", count: 2)
      end
    end
  end
end
