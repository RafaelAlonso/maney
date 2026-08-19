require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#brl" do
    it { expect(helper.brl(nil)).to eq "—" }
    it { expect(helper.brl(0)).to eq "R$ 0,00" }
    it { expect(helper.brl(123_456_789)).to eq "R$ 1.234.567,89" }
    it { expect(helper.brl(-1_234)).to eq "-R$ 12,34" }
    it { expect(helper.brl(-123_456_789)).to eq "-R$ 1.234.567,89" }
  end

  describe "#statement_due_label" do
    let(:card) { create_card }

    it "omits the year when the due date falls in the current one" do
      statement = Budgeting::StatementAttribution.statement_for(card:, date: Date.new(2026, 3, 6))

      expect(helper.statement_due_label(statement, today: Date.new(2026, 3, 20))).to eq "vence 13/04"
    end

    it "shows the year across the rollover, so January/2027 can't be read as this year" do
      statement = Budgeting::StatementAttribution.statement_for(card:, date: Date.new(2026, 12, 10))

      expect(helper.statement_due_label(statement, today: Date.new(2026, 12, 20))).to eq "vence 12/01/2027"
    end
  end

  describe "#statement_period_label" do
    def row(period_start, period_end)
      Budgeting::CardStatements::Row.new(statement: nil, expenses: [], total_cents: 0,
                                         period_start:, period_end:)
    end

    it "omits the year when the whole period falls in the current one" do
      label = helper.statement_period_label(row(Date.new(2026, 3, 5), Date.new(2026, 4, 2)),
                                            today: Date.new(2026, 3, 20))

      expect(label).to eq "05/03 – 02/04"
    end

    it "shows the year when the period crosses into another one" do
      label = helper.statement_period_label(row(Date.new(2026, 12, 4), Date.new(2027, 1, 4)),
                                            today: Date.new(2026, 12, 20))

      expect(label).to eq "04/12/2026 – 04/01/2027"
    end
  end

  # Rails' `pluralize` inflects only the last word — right for English, wrong for
  # Portuguese, where the plural agrees across the noun phrase. It produced
  # "3 gasto avulsos" in the card-deletion flow, three times over.
  describe "#pt_pluralize" do
    it "uses the singular for exactly one" do
      expect(helper.pt_pluralize(1, "gasto avulso", "gastos avulsos")).to eq "1 gasto avulso"
    end

    it "inflects every word of the phrase in the plural" do
      expect(helper.pt_pluralize(3, "gasto avulso", "gastos avulsos")).to eq "3 gastos avulsos"
      expect(helper.pt_pluralize(2, "compra parcelada", "compras parceladas")).to eq "2 compras parceladas"
    end

    it "uses the plural for zero, as Portuguese does" do
      expect(helper.pt_pluralize(0, "gasto avulso", "gastos avulsos")).to eq "0 gastos avulsos"
    end
  end

  # A due day that doesn't come after the closing day is valid — the engine rolls
  # the due date into the following month — but on screen it reads as a typo, and
  # nothing distinguished it from one.
  describe "#card_days_label" do
    def schedule(closing_day:, due_day:)
      Budgeting::Schedule.new(closing_day:, due_day:, valid_from: Date.new(2026, 3, 1))
    end

    it "states the days plainly when the statement is due in the closing month" do
      expect(helper.card_days_label(schedule(closing_day: 5, due_day: 12)))
        .to eq "fecha dia 5 · vence dia 12"
    end

    it "says the statement is due the following month when the due day comes first" do
      expect(helper.card_days_label(schedule(closing_day: 20, due_day: 12)))
        .to eq "fecha dia 20 · vence dia 12 (vence no mês seguinte)"
    end

    it "treats equal days as due the following month" do
      expect(helper.card_days_label(schedule(closing_day: 10, due_day: 10)))
        .to include("(vence no mês seguinte)")
    end
  end

  describe "#month_label" do
    it "gives the month alone inside the current year" do
      expect(helper.month_label(Date.new(2026, 8, 1), today: Date.new(2026, 8, 10))).to eq "ago"
    end

    it "adds the year once the month leaves the current one" do
      expect(helper.month_label(Date.new(2028, 1, 1), today: Date.new(2026, 8, 10))).to eq "jan/2028"
    end
  end

  describe "#nav_active?" do
    it "is true when the current controller is one of the given names" do
      allow(helper.controller).to receive(:controller_name).and_return("statements")
      expect(helper.nav_active?("cards", "statements", "card_migrations", "card_archivals")).to be true
    end

    it "is false when the current controller is none of them" do
      allow(helper.controller).to receive(:controller_name).and_return("home")
      expect(helper.nav_active?("expenses")).to be false
    end
  end

  describe "#nav_destinations" do
    it "lists the seven destinations in nav order" do
      expect(helper.nav_destinations.map { |d| d[:label] }).to eq(
        %w[Início Gastos Ganhos Cartões Categorias Análise Config]
      )
    end
  end
end
