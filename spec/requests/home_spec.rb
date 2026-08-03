require "rails_helper"

RSpec.describe "Home month view", type: :request do
  let(:march) { Date.new(2026, 3, 1) }
  before { create_setting!(first_month: march); create_reserved_categories! }

  it "shows both balances, the credit-card line and the AC 2 numbers" do
    mercado = Category.create!(name: "mercado")
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 400_000)
    Expense.create!(name: "feira", amount_cents: 100_000, date: Date.new(2026, 3, 5),
                    payment_method: "debit", category: mercado)
    card = create_card!
    # 120.000 credit purchase closing 05/03, due 12/03 → statement in March
    Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card:, category: mercado)
    get root_path(month: "2026-03")
    expect(response.body).to include("saldo estimado").and include("saldo atual")
    expect(response.body).to include("cartão de crédito")
    # mercado: max(4.000 budget − 1.200 credit, 1.000 cash) = 2.800; statement due 1.200
    # estimate = 5.000 − 2.800 − 1.200 = 1.000 ; current = 5.000 − 1.000 debit = 4.000
    expect(response.body).to include("R$ 1.000,00").and include("R$ 4.000,00")
  end

  # The example above used to be the only one rendering a negative estimate, and
  # it stopped being negative when the estimate became a cash forecast. The red
  # emphasis in home/_balances is unchanged behavior, so it keeps a test.
  it "keeps the red emphasis on a negative estimate" do
    mercado = Category.create!(name: "mercado")
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    Budget.create!(category: mercado, month: march, amount_cents: 120_000)

    get root_path(month: "2026-03")

    expect(response.body).to include("-R$ 200,00")
    expect(response.body).to include("text-red-700")
  end

  it "reflects a statement payment in the current balance, not the estimate (AC 2)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    Expense.create!(name: "fatura", amount_cents: 120_000, date: Date.new(2026, 3, 12),
                    payment_method: "debit", category: credit_card_category)
    get root_path(month: "2026-03")
    # current = 5000 − 1200 payment = 3800 (no other debit); estimate unaffected by the payment
    expect(response.body).to include("R$ 3.800,00")
  end

  it "highlights a category that overran its budget (AC 3)" do
    mercado = Category.create!(name: "mercado")
    Budget.create!(category: mercado, month: march, amount_cents: 90_000)
    Expense.create!(name: "feira", amount_cents: 150_000, date: Date.new(2026, 3, 5),
                    payment_method: "debit", category: mercado)
    get root_path(month: "2026-03")
    expect(response.body).to match(/text-red-700[^>]*>\s*gasto R\$ 1\.500,00/)
  end

  it "opens an empty month with zeros and no error (AC 12)" do
    Category.create!(name: "mercado")
    get root_path(month: "2026-03")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("orçado R$ 0,00")
  end

  it "carries the previous month's closing balance into the next, live (AC 6/7)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: march) # March closes at 5000
    get root_path(month: "2026-04")
    expect(response.body).to include("R$ 5.000,00") # April current balance = carried 5000
    Expense.create!(name: "retro", amount_cents: 30_000, date: Date.new(2026, 3, 20),
                    payment_method: "debit", category: Category.create!(name: "mercado"))
    get root_path(month: "2026-04")
    expect(response.body).to include("R$ 4.700,00") # retroactive March debit ripples forward
  end

  it "navigates to another month (AC 4)" do
    get root_path(month: "2026-04")
    expect(response.body).to include("04/2026")
  end

  # The clamp used to be invisible in the address bar: the page showed 03/2026
  # while the URL still said 2025-01, so a bookmarked or shared link named a
  # month it doesn't open. The URL is now rewritten to the month rendered.
  it "clamps a month before the first month up to the first month, and says so in the URL" do
    get root_path(month: "2025-01")
    expect(response).to redirect_to(root_path(month: "2026-03"))
    follow_redirect!
    expect(response.body).to include("03/2026")
    expect(response.body).not_to include("01/2025")
  end

  it "falls back to the current month on an unparseable month, and says so in the URL" do
    get root_path(month: "banana")
    expect(response).to redirect_to(root_path(month: Date.current.strftime("%Y-%m")))
  end

  it "shows the FAB with both actions" do
    get root_path
    expect(response.body).to include(new_expense_path).and include(new_income_path)
  end

  it "shows a red alert when next month's statements exceed the current balance (AC 9)" do
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 120_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).to include("ultrapassam o saldo atual")
  end

  it "shows a yellow alert at/above the threshold (AC 9)" do
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 85_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).to include("se aproximam do saldo atual")
  end

  it "shows no alert below the threshold (AC 9)" do
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 70_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).not_to include("saldo atual deste mês")
  end

  it "respects the configured threshold (AC 10)" do
    Setting.instance.update!(alert_threshold_percent: 90)
    Income.create!(name: "salário", amount_cents: 100_000, date: march)
    card = create_card!
    Expense.create!(name: "compra", amount_cents: 85_000, date: Date.new(2026, 3, 6),
                    payment_method: "credit", card:, category: Category.create!(name: "mercado"))
    get root_path(month: "2026-03")
    expect(response.body).not_to include("se aproximam")
  end

  it "projects a future month: inherited budget and projected spending (AC 11)" do
    card = create_card!
    casa = Category.create!(name: "casa")
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                date: Date.new(2026, 3, 10), card:, category: casa)
    get root_path(month: "2026-06")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("06/2026")
    # casa spends 10.000 in June and inherits May's 10.000 as June's budget
    expect(response.body).to include("gasto R$ 100,00").and include("orçado R$ 100,00")
  end

  # AC 1 asks the month view for "income with a total". It rendered neither, and
  # /incomes had no total either, so the month's income was displayed nowhere —
  # leaving "saldo estimado" impossible to sanity-check without adding it up by hand.
  describe "the income block (AC 1)" do
    it "lists the month's income with a total that includes the carried balance" do
      Setting.instance.update!(initial_balance_cents: 200_000)
      Income.create!(name: "salário", amount_cents: 500_000, date: march)
      Income.create!(name: "freela", amount_cents: 50_000, date: Date.new(2026, 3, 20))

      get root_path(month: "2026-03")

      expect(response.body).to include("ganhos").and include("salário").and include("freela")
      expect(response.body).to include("saldo inicial")
      # 2.000 carried + 5.000 + 500
      expect(response.body).to include("R$ 7.500,00")
    end

    it "names the carried balance as the previous month's outside the first month" do
      get root_path(month: "2026-04")

      expect(response.body).to include("saldo do mês anterior")
    end
  end

  # `spent > budgeted` painted every unbudgeted category red, so in the first
  # month — and in any month with a new category — the real overrun carried
  # exactly the same styling as four categories the user simply hadn't budgeted yet.
  it "does not paint a category without a budget as an overrun (AC 3)" do
    mercado = Category.create!(name: "mercado")
    Expense.create!(name: "feira", amount_cents: 150_000, date: Date.new(2026, 3, 5),
                    payment_method: "debit", category: mercado)

    get root_path(month: "2026-03")

    row = Nokogiri::HTML(response.body).at("##{ActionView::RecordIdentifier.dom_id(mercado, :row)}")
    expect(row.to_html).to include("orçado R$ 0,00")
    expect(row.to_html).not_to include("text-red-700")
  end

  # The month's card row expands into one line per statement due that month.
  # Three cards on three closing days, all due in March 2026:
  #   Azul  closes  3 / due 10 — purchase 02/03 -> statement due 10/03
  #   Roxo  closes  8 / due 15 — purchase 05/03 -> closing moves back to Fri 06/03,
  #                              so the purchase still lands here; due 15/03 is a
  #                              Sunday, so it moves forward to 16/03
  #   Verde closes 15 / due 25 — purchase 05/03 -> statement due 25/03
  # 2.100 + 1.450 + 760 = 4.310.
  describe "the credit-card breakdown" do
    def credit_expense(amount, date, on:)
      Expense.create!(name: "compra", amount_cents: amount, date:, payment_method: "credit",
                      card: on, category: Category.find_or_create_by!(name: "mercado"))
    end

    def three_cards
      azul = create_card!(name: "Azul", closing_day: 3, due_day: 10)
      roxo = create_card!(name: "Roxo", closing_day: 8, due_day: 15)
      verde = create_card!(name: "Verde", closing_day: 15, due_day: 25)
      credit_expense(210_000, Date.new(2026, 3, 2), on: azul)
      credit_expense(145_000, Date.new(2026, 3, 5), on: roxo)
      credit_expense(76_000, Date.new(2026, 3, 5), on: verde)
      [ azul, roxo, verde ]
    end

    def card_row
      Nokogiri::HTML(response.body)
        .at("##{ActionView::RecordIdentifier.dom_id(credit_card_category, :row)}")
    end

    it "lists each card with its amount and due date under the consolidated total (AC 1)" do
      three_cards

      get root_path(month: "2026-03")

      row = card_row
      expect(row.name).to eq "details"
      expect(row.at("summary").text).to include("orçado R$ 4.310,00")
      lines = row.css("li").map { |li| li.text.gsub(/\s+/, " ").strip }
      expect(lines.size).to eq 3
      expect(lines[0]).to include("Azul").and include("vence 10/03").and include("R$ 2.100,00")
      expect(lines[1]).to include("Roxo").and include("vence 16/03").and include("R$ 1.450,00")
      expect(lines[2]).to include("Verde").and include("vence 25/03").and include("R$ 760,00")
    end

    it "links each line to that card's statement (AC 2)" do
      azul, roxo, verde = three_cards

      get root_path(month: "2026-03")

      hrefs = card_row.css("li a").map { |a| a["href"] }
      expect(hrefs).to eq [
        card_statement_path(azul, "2026-03-03"),
        card_statement_path(roxo, "2026-03-08"),
        card_statement_path(verde, "2026-03-15")
      ]
    end

    it "resolves a breakdown link to that card's statement for the month (AC 2)" do
      azul, = three_cards
      get root_path(month: "2026-03")
      href = card_row.at("li a")["href"]

      get href

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Azul").and include("vence 10/03")
                                              .and include("R$ 2.100,00")
    end

    it "omits a card with nothing due in the month (AC 3)" do
      three_cards
      preto = create_card!(name: "Preto", closing_day: 20, due_day: 27)
      # Bought after Preto's 20/03 closing, so it falls due on 27/04 — not this month.
      credit_expense(50_000, Date.new(2026, 3, 25), on: preto)

      get root_path(month: "2026-03")

      row = card_row
      expect(row.css("li").size).to eq 3
      expect(row.text).not_to include("Preto")
      expect(row.at("summary").text).to include("orçado R$ 4.310,00")
    end

    it "shows one line whose amount equals the total for a single card (AC 7)" do
      card = create_card!(name: "Azul", closing_day: 3, due_day: 10)
      credit_expense(210_000, Date.new(2026, 3, 2), on: card)

      get root_path(month: "2026-03")

      row = card_row
      expect(row.css("li").size).to eq 1
      expect(row.at("li").text).to include("Azul").and include("R$ 2.100,00")
      expect(row.at("summary").text).to include("orçado R$ 2.100,00")
    end

    it "offers nothing to expand when no card has a statement due (AC 8)" do
      get root_path(month: "2026-03")

      row = card_row
      expect(row.name).to eq "div"
      expect(row.to_html).not_to include("<details")
      expect(row.text).to include("orçado R$ 0,00")
      expect(row.text).to include("cartão de crédito")
    end

    it "highlights the card row when statement payments exceed the statements due" do
      card = create_card!(closing_day: 3, due_day: 10)
      credit_expense(100_000, Date.new(2026, 3, 2), on: card) # statement due this month: 1.000
      # A payment settling an overdue statement from before, larger than what's due now.
      Expense.create!(name: "fatura", amount_cents: 150_000, date: Date.new(2026, 3, 15),
                      payment_method: "debit", category: credit_card_category)

      get root_path(month: "2026-03")

      expect(card_row.to_html).to match(/text-red-700[^>]*>\s*gasto R\$ 1\.500,00/)
    end

    it "does not highlight the card row when statement payments stay within the statements due" do
      card = create_card!(closing_day: 3, due_day: 10)
      credit_expense(100_000, Date.new(2026, 3, 2), on: card) # statement due this month: 1.000
      Expense.create!(name: "fatura", amount_cents: 60_000, date: Date.new(2026, 3, 15),
                      payment_method: "debit", category: credit_card_category)

      get root_path(month: "2026-03")

      expect(card_row.to_html).not_to include("text-red-700")
    end
  end
end
