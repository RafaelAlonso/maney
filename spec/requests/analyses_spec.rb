require "rails_helper"

RSpec.describe "Analysis", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }

  def selected_year
    Nokogiri::HTML(response.body).at_css("option[selected]")&.[]("value")
  end

  it "opens on the current year and offers every year since the first month (AC 1)" do
    travel_to(Date.new(2027, 5, 10)) do
      get analysis_path
      expect(response.body).to include("2027").and include("2026")
    end
  end

  it "shows the year asked for (AC 1)" do
    travel_to(Date.new(2027, 5, 10)) do
      get analysis_path(year: 2026)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("2026")
    end
  end

  it "clamps a year before the first month up to the first year" do
    travel_to(Date.new(2026, 7, 1)) do
      get analysis_path(year: 1999)
      expect(response).to have_http_status(:ok)
      expect(selected_year).to eq "2026"
    end
  end

  it "clamps a future year down to the current one" do
    travel_to(Date.new(2026, 7, 1)) do
      get analysis_path(year: 2099)
      expect(response).to have_http_status(:ok)
      expect(selected_year).to eq "2026"
    end
  end

  it "survives a non-numeric year" do
    travel_to(Date.new(2026, 7, 1)) do
      get analysis_path(year: "banana")
      expect(response).to have_http_status(:ok)
    end
  end

  it "renders a plain message for a year with no entries (AC 11)" do
    travel_to(Date.new(2026, 7, 1)) do
      get analysis_path
      expect(response.body).to include("Nenhum lançamento em 2026")
    end
  end

  it "renders the charts once the year has entries" do
    Expense.create!(name: "feira", amount_cents: 5_000, payment_method: "debit",
                    category: mercado, date: Date.new(2026, 3, 4))
    travel_to(Date.new(2026, 7, 1)) do
      get analysis_path
      expect(response.body).not_to include("Nenhum lançamento")
    end
  end

  it "links to the section from the top navigation" do
    get root_path
    expect(response.body).to include("Análise").and include(analysis_path)
  end
end
