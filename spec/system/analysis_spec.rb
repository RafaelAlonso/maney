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
end
