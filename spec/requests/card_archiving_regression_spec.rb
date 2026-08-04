require "rails_helper"

# Archiving must be invisible to the money. The financial engine
# (app/models/budgeting/*) never learns about archiving, and this spec is what
# holds that line: if anyone ever adds `.active` to a card query in a statement,
# a total, a chart, the forecast balance or the committed debt, every example
# here fails. `Card.active` belongs in exactly one place —
# ApplicationHelper#card_options_for.
RSpec.describe "Archiving a card moves no money", type: :request do
  let(:march) { Date.new(2026, 3, 1) }
  let(:mercado) { category("mercado") }

  # Every "R$ 1.234,56" / "-R$ 12,00" on the page, in document order.
  def money_on(path)
    get path
    expect(response).to have_http_status(:ok)
    response.body.scan(/-?R\$&nbsp;[\d.,]+|-?R\$ [\d.,]+/)
  end

  before do
    create_setting!(first_month: march)
    create_reserved_categories!
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 400_000)
  end

  # A card carrying both a settled past and an open present: one statement
  # already paid, one still unpaid and due this month. Both must keep counting.
  let!(:card) { create_card!(name: "Preto", closing_day: 5, due_day: 12) }

  let!(:paid_purchase) do
    Expense.create!(name: "compra de março", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card:, category: mercado)
  end

  let!(:statement_payment) do
    Expense.create!(name: "fatura de março", amount_cents: 120_000, date: Date.new(2026, 3, 12),
                    payment_method: "debit", category: credit_card_category)
  end

  let!(:open_purchase) do
    Expense.create!(name: "compra de abril", amount_cents: 80_000, date: Date.new(2026, 4, 3),
                    payment_method: "credit", card:, category: mercado)
  end

  # Installments running years out — the story's "installments years out keep
  # counting in committed debt" edge case.
  let!(:installments) do
    InstallmentPurchase.create!(name: "geladeira", total_cents: 240_000, date: Date.new(2026, 4, 2),
                                category: mercado, card:, installments_count: 12,
                                first_installment: 1)
  end

  it "leaves every figure on the month screen identical (ACs 4, 5)" do
    %w[2026-03 2026-04].each do |month|
      before_archiving = money_on(root_path(month:))
      expect(before_archiving).not_to be_empty

      card.archive!

      expect(money_on(root_path(month:))).to eq before_archiving

      card.reactivate!
    end
  end

  it "leaves the committed debt and the whole Análise screen identical (AC 5)" do
    before_archiving = money_on(analysis_path)
    expect(before_archiving).not_to be_empty

    card.archive!

    expect(money_on(analysis_path)).to eq before_archiving
  end

  it "keeps the archived card's full statement history reachable (AC 6)" do
    before_archiving = money_on(card_statements_path(card))
    expect(before_archiving).not_to be_empty

    card.archive!

    expect(money_on(card_statements_path(card))).to eq before_archiving
    expect(response.body).to include("Preto")
  end

  it "keeps the archived card's unpaid statement in the month's expense list (AC 5)" do
    card.archive!

    get expenses_path(month: "2026-04")

    expect(response.body).to include("Preto")
  end
end
