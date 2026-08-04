require "rails_helper"

RSpec.describe "Analysis", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before { create_setting!(first_month: Date.new(2026, 3, 1)); create_reserved_categories! }

  let(:mercado) { Category.create!(name: "mercado") }

  # Scoped to the year select: once the card selector ships alongside it, a
  # filtered card's own selected option would otherwise be the first
  # "option[selected]" in document order and shadow the year's.
  def selected_year
    Nokogiri::HTML(response.body).at_css("select[name='year'] option[selected]")&.[]("value")
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

  describe "the committed-debt block" do
    let(:azul) { create_card! }

    def credit(cents, on:)
      Expense.create!(name: "compra", amount_cents: cents, payment_method: "credit",
                      category: mercado, card: azul, date: on)
    end

    it "sits above the year picker, which does not govern it" do
      travel_to(Date.new(2026, 8, 10)) { get analysis_path }

      expect(response.body.index("Dívida já comprometida"))
        .to be < response.body.index("name=\"year\"")
    end

    it "shows even on a year with no entries at all" do
      travel_to(Date.new(2026, 8, 10)) { get analysis_path }

      expect(response.body).to include("Nenhum lançamento em 2026")
        .and include("Dívida já comprometida")
    end

    it "states that there is no committed card debt when there is none (AC 8)" do
      travel_to(Date.new(2026, 8, 10)) { get analysis_path }

      expect(response.body).to include("Não há dívida comprometida no cartão")
    end

    it "names the month the debt passes the balance and the amount short (AC 3)" do
      Setting.instance.update!(initial_balance_cents: 500_000)
      credit(624_000, on: Date.new(2026, 8, 4))

      travel_to(Date.new(2026, 8, 10)) { get analysis_path }

      expect(response.body).to include("Em ago a dívida passa o saldo").and include("R$ 1.240,00")
    end

    it "says the debt is covered when the balance carries it (AC 4)" do
      Setting.instance.update!(initial_balance_cents: 500_000)
      credit(120_000, on: Date.new(2026, 8, 4))

      travel_to(Date.new(2026, 8, 10)) { get analysis_path }

      expect(response.body).to include("O saldo cobre a dívida já comprometida")
    end

    it "states what the comparison leaves out (AC 5)" do
      travel_to(Date.new(2026, 8, 10)) { get analysis_path }

      expect(response.body).to include("Não inclui receitas futuras nem gastos comuns futuros")
    end
  end

  describe "the card selector" do
    let(:azul) { create_card!(name: "Azul") }
    let(:preto) { create_card!(name: "Preto") }

    def credit(cents, on:, card:)
      Expense.create!(name: "compra", amount_cents: cents, payment_method: "credit",
                      category: mercado, card:, date: on)
    end

    def debit(cents, on:)
      Expense.create!(name: "feira", amount_cents: cents, payment_method: "debit",
                      category: mercado, date: on)
    end

    # Every chart ships its Chart.js config as a JSON data attribute, so the
    # numbers actually plotted are assertable straight off the response.
    def spending_bars
      node = Nokogiri::HTML(response.body).at_css("[data-chart-config-value]")
      JSON.parse(node["data-chart-config-value"]).dig("data", "datasets", 0, "data")
    end

    def selected_card
      Nokogiri::HTML(response.body).at_css("select[name='card_id'] option[selected]")&.[]("value")
    end

    # A chart's config as it was shipped to the browser, found by its heading —
    # the profit chart mounts its own Stimulus controller on the <section> itself
    # rather than on a descendant, hence checking the section's own attribute
    # before falling back to a descendant (Nokogiri's css/at_css never match the
    # context node itself, only its descendants).
    def config_for(body, title)
      section = Nokogiri::HTML(body).css("section").find { |s| s.at_css("h2")&.text&.include?(title) }
      section["data-profit-chart-config-value"] ||
        section.at_css("[data-chart-config-value]")["data-chart-config-value"]
    end

    it "defaults to every card and totals the consolidated year (AC 1)" do
      credit(10_000, on: Date.new(2026, 3, 4), card: azul)
      credit(4_000, on: Date.new(2026, 3, 5), card: preto)

      travel_to(Date.new(2026, 7, 1)) { get analysis_path }

      expect(selected_card).to be_nil
      expect(response.body).to include("Todos os cartões")
      expect(spending_bars[2]).to eq 140.0
    end

    it "narrows the spending charts to the selected card (AC 2)" do
      credit(10_000, on: Date.new(2026, 3, 4), card: azul)
      credit(4_000, on: Date.new(2026, 3, 5), card: preto)

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: azul.id) }

      expect(selected_card).to eq azul.id.to_s
      expect(spending_bars[2]).to eq 100.0
    end

    it "counts a purchase in its purchase month, not its statement month (AC 3)" do
      # Azul closes on day 5: this March purchase falls due in April.
      credit(15_000, on: Date.new(2026, 3, 20), card: azul)

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: azul.id) }

      expect(spending_bars[2]).to eq 150.0
      expect(spending_bars[3]).to eq 0.0
    end

    it "leaves debit and cash spending out of a filtered chart (AC 4)" do
      credit(10_000, on: Date.new(2026, 3, 4), card: azul)
      debit(9_900, on: Date.new(2026, 3, 6))

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: azul.id) }

      expect(spending_bars[2]).to eq 100.0
    end

    it "returns to the consolidated reading when the card is cleared (AC 6)" do
      credit(10_000, on: Date.new(2026, 3, 4), card: azul)
      credit(4_000, on: Date.new(2026, 3, 5), card: preto)

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: "") }

      expect(selected_card).to be_nil
      expect(spending_bars[2]).to eq 140.0
    end

    it "keeps the card when the year changes, and the year when the card does (AC 7)" do
      credit(10_000, on: Date.new(2026, 3, 4), card: azul)
      credit(7_000, on: Date.new(2027, 2, 4), card: azul)

      travel_to(Date.new(2027, 5, 10)) { get analysis_path(card_id: azul.id, year: 2027) }

      expect(selected_card).to eq azul.id.to_s
      expect(selected_year).to eq "2027"
      expect(spending_bars[1]).to eq 70.0
    end

    # One form carries both controls, which is what makes the two independent:
    # a GET submit sends every field it holds, so neither can drop the other.
    it "puts both selects in a single form" do
      azul
      travel_to(Date.new(2026, 7, 1)) { get analysis_path }

      forms = Nokogiri::HTML(response.body).css("form").select do |form|
        form.css("select[name='card_id']").any? && form.css("select[name='year']").any?
      end
      expect(forms.size).to eq 1
    end

    # AC 9 also promises archived cards stay listed, but Card has no
    # archiving concept yet (no archived_at, no Card.active scope) — the
    # controller's guard against a future `Card.active` reaching this screen
    # is a code comment for now. That half of AC 9 gets a real test once the
    # sibling story w1-story-card-archiving introduces the scope.
    it "lists every card in the system" do
      azul
      preto
      travel_to(Date.new(2026, 7, 1)) { get analysis_path }

      options = Nokogiri::HTML(response.body).css("select[name='card_id'] option").map(&:text)
      expect(options).to contain_exactly("Todos os cartões", "Azul", "Preto")
    end

    it "falls back to every card on an unknown card_id rather than raising" do
      credit(10_000, on: Date.new(2026, 3, 4), card: azul)

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: 999_999) }

      expect(response).to have_http_status(:ok)
      expect(selected_card).to be_nil
      expect(spending_bars[2]).to eq 100.0
    end

    it "keeps the all-cards charts whole and says so (AC 5)" do
      Income.create!(name: "salário", amount_cents: 100_000, date: Date.new(2026, 3, 5))
      credit(10_000, on: Date.new(2026, 3, 4), card: azul)
      credit(4_000, on: Date.new(2026, 3, 5), card: preto)
      debit(3_000, on: Date.new(2026, 3, 6))

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: azul.id) }
      filtered_body = response.body

      travel_to(Date.new(2026, 7, 1)) { get analysis_path }
      consolidated_body = response.body

      expect(config_for(filtered_body, "Lucro por mês")).to eq config_for(consolidated_body, "Lucro por mês")
      expect(config_for(filtered_body, "Gastos e saídas")).to eq config_for(consolidated_body, "Gastos e saídas")
      expect(filtered_body.scan("Cobre todos os cartões").size).to eq 2
      expect(consolidated_body).not_to include("Cobre todos os cartões")
    end

    it "shows an empty state instead of a blank chart for a card with no spending (AC 8)" do
      Income.create!(name: "salário", amount_cents: 100_000, date: Date.new(2026, 3, 5))
      debit(3_000, on: Date.new(2026, 3, 6))
      azul

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: azul.id) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum gasto em Azul em 2026.")
      expect(response.body).not_to include("Nenhum lançamento em 2026")
      # The two spending charts lose their canvas; profit and gastos-e-saídas keep theirs.
      expect(Nokogiri::HTML(response.body).css("canvas").size).to eq 2
    end

    # The AC 8 example above seeds an Income and a debit expense before
    # filtering, which keeps #any_data? true on the unfiltered path too and
    # cannot catch a gate that reads the filtered analysis instead of the
    # consolidated one. This example seeds neither, so the year has no
    # unfiltered data of its own — only credit spending on another card.
    it "renders the whole-year panels for a card with no spending in an otherwise-empty year" do
      credit(4_000, on: Date.new(2026, 3, 5), card: preto)

      travel_to(Date.new(2026, 7, 1)) { get analysis_path(card_id: azul.id) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum gasto em Azul em 2026.")
      expect(response.body).not_to include("Nenhum lançamento")
      expect(Nokogiri::HTML(response.body).css("canvas").size).to eq 2
    end
  end
end
