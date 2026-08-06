require "rails_helper"

RSpec.describe "PWA", type: :request do
  describe "the manifest" do
    it "describes Maney as a standalone app in its own colours (AC 1, 2)" do
      get pwa_manifest_path(format: :json)

      manifest = JSON.parse(response.body)
      expect(manifest["name"]).to eq "Maney"
      expect(manifest["short_name"]).to eq "Maney"
      expect(manifest["display"]).to eq "standalone"
      expect(manifest["start_url"]).to eq "/"
      expect(manifest["scope"]).to eq "/"
      expect(manifest["theme_color"]).to eq "#059669"
      expect(manifest["background_color"]).to eq "#f9fafb"
    end

    it "offers every icon size an installer needs, including a maskable one (AC 1, 3)" do
      get pwa_manifest_path(format: :json)

      icons = JSON.parse(response.body)["icons"]
      expect(icons.map { |icon| icon["sizes"] }).to include("192x192", "512x512")
      expect(icons.map { |icon| icon["purpose"] }).to include("maskable")
    end
  end

  describe "the layout head" do
    before { create_setting!; create_reserved_categories! }

    it "links the manifest and declares the theme colour" do
      get root_path

      expect(response.body).to include('rel="manifest"')
      expect(response.body).to include('name="theme-color"')
      expect(response.body).to include("#059669")
    end

    # Without this meta, iOS names the home-screen icon after <title>, which
    # every screen that sets content_for(:title) overrides — installing from
    # Análise would produce an app called "Análise".
    it "names the installed app Maney on iOS whatever the page title is (AC 1, 3)" do
      get analysis_path

      expect(response.body).to include("<title>Análise</title>")
      expect(response.body).to include('<meta name="apple-mobile-web-app-title" content="Maney">')
    end
  end
end
