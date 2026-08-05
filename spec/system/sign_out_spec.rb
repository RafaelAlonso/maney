require "rails_helper"

RSpec.describe "Signing out", type: :system do
  before { create_setting!; create_reserved_categories! }

  it "returns to the sign-in screen from Config (AC 4)" do
    visit edit_settings_path

    click_button "sair"

    expect(page).to have_content("Entrar")
    expect(page).to have_no_link("Categorias")
  end
end
