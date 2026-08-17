require "rails_helper"

RSpec.describe "Theming", type: :system do
  before { create_setting!; create_reserved_categories! }

  it "follows a dark device when there is no manual override (AC1)" do
    set_prefers_color_scheme(:dark)
    visit root_path
    expect(page).to have_css("html:not(.light):not(.dark)")
    expect(background_of("body")).to eq(rgb("#0b0f14"))
  end

  it "follows a light device when there is no override (AC2)" do
    set_prefers_color_scheme(:light)
    visit root_path
    expect(background_of("body")).to eq(rgb("#f8fafc"))
  end

  it "honors the persisted manual override on a later visit (AC3)" do
    set_prefers_color_scheme(:light)
    visit root_path
    click_button "Tema"                 # flip to dark
    expect(page).to have_css("html.dark")
    visit root_path                     # revisit
    expect(page).to have_css("html.dark") # server read the cookie, no flash
  end
end
