require "rails_helper"

RSpec.describe "Privacy policy", type: :request do
  # AC 11: reachable from inside the app at any time, in Portuguese, saying what
  # is collected, why, how long it is kept and how to delete it.
  it "states the four things the law requires it to state" do
    get privacy_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("O que coletamos")
    expect(response.body).to include("Por que coletamos")
    expect(response.body).to include("Por quanto tempo")
    expect(response.body).to include("Como excluir")
  end

  # The invitation acceptance screen is opened by someone with no account, so
  # the policy cannot be behind the sign-in wall.
  it "is readable without signing in and without the app being set up" do
    sign_out_request

    get privacy_path

    expect(response).to have_http_status(:ok)
  end

  it "is linked from Config" do
    create_setting!
    create_reserved_categories!

    get edit_settings_path

    expect(response.body).to include(privacy_path)
  end

  it "renders the privacy page in the design system (AC 7)" do
    get privacy_path

    expect(response.body).to include("text-text")
    expect(response.body).not_to include("text-gray-700")
  end
end
