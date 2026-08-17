require "rails_helper"

RSpec.describe "Theme class on <html>", type: :request do
  before { create_setting!; create_reserved_categories! }

  it "stamps class=\"dark\" when the theme cookie is dark" do
    cookies[:theme] = "dark"
    get root_path
    expect(response.body).to include('<html lang="pt-BR" class="dark">')
  end

  it "stamps class=\"light\" when the theme cookie is light" do
    cookies[:theme] = "light"
    get root_path
    expect(response.body).to include('<html lang="pt-BR" class="light">')
  end

  it "stamps no theme class when the cookie is absent (device-follow)" do
    get root_path
    expect(response.body).to include('<html lang="pt-BR">')
  end

  it "ignores an unexpected cookie value" do
    cookies[:theme] = "chartreuse"
    get root_path
    expect(response.body).to include('<html lang="pt-BR">')
  end

  it "renders the body on design-system tokens" do
    get root_path
    expect(response.body).to include('class="min-h-screen bg-bg text-text pb-24"')
  end
end
