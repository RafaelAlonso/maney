require "rails_helper"

RSpec.describe "shared/_budget_bar", type: :view do
  before { allow(Setting).to receive(:instance).and_return(double(alert_threshold_percent: 80)) }

  it "paints on-track below the threshold and fills proportionally" do
    render "shared/budget_bar", spent_cents: 2500, budgeted_cents: 10_000
    expect(rendered).to have_css("div.progress-fill.progress-on_track")
    expect(rendered).to have_css('div.progress-fill[style*="width: 25%"]')
  end

  it "paints near at the threshold" do
    render "shared/budget_bar", spent_cents: 8000, budgeted_cents: 10_000
    expect(rendered).to have_css("div.progress-fill.progress-near")
  end

  it "paints over above budget, capped at 100%" do
    render "shared/budget_bar", spent_cents: 15_000, budgeted_cents: 10_000
    expect(rendered).to have_css('div.progress-fill.progress-over[style*="width: 100%"]')
  end

  it "paints neutral for an unbudgeted category" do
    render "shared/budget_bar", spent_cents: 5000, budgeted_cents: 0
    expect(rendered).to have_css("div.progress-fill.progress-neutral")
  end
end
