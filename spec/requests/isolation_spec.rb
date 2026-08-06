require "rails_helper"

# AC 5 and AC 6: two people, each with a full budget, and nothing of one
# reaching any screen of the other.
RSpec.describe "Isolation between people", type: :request do
  let(:march) { Date.new(2026, 3, 1) }
  let(:other) { create_user!(email_address: "outra@example.com") }

  # The signed-in person: card "Azul", closing on the 5th.
  before do
    create_setting!(first_month: march)
    create_reserved_categories!
    @mercado = Category.create!(name: "mercado")
    @card = create_card!(name: "Azul")
    Income.create!(name: "salário", amount_cents: 500_000, date: march)
    Budget.create!(category: @mercado, month: march, amount_cents: 400_000)
    Expense.create!(name: "feira", amount_cents: 100_000, date: Date.new(2026, 3, 5),
                    payment_method: "debit", category: @mercado)
  end

  # The other person: everything named distinctly, so a leak is a visible string.
  let!(:their) do
    as(other) do
      create_setting!(first_month: march)
      create_reserved_categories!
      farmacia = Category.create!(name: "farmácia")
      card = create_card!(name: "Roxo", closing_day: 20, due_day: 27)
      income = Income.create!(name: "aluguel-recebido", amount_cents: 900_000, date: march)
      expense = Expense.create!(name: "remédio", amount_cents: 700_000, date: Date.new(2026, 3, 6),
                                payment_method: "debit", category: farmacia)
      Budget.create!(category: farmacia, month: march, amount_cents: 800_000)
      { category: farmacia, card:, income:, expense: }
    end
  end

  # Every distinctive string the other person owns. A local, not a constant —
  # `LEAKS = ...` inside a block is a dynamic constant assignment and will not
  # parse.
  let(:leaks) { %w[farmácia Roxo aluguel-recebido remédio] }

  it "keeps the other person off every screen (AC 5)" do
    [ root_path(month: "2026-03"), expenses_path(month: "2026-03"), incomes_path(month: "2026-03"),
      cards_path, categories_path, analysis_path ].each do |path|
      get path

      expect(response).to have_http_status(:ok), "#{path} did not render"
      leaks.each { |leak| expect(response.body).not_to include(leak), "#{path} leaked #{leak}" }
    end
  end

  # `edit_settings_path` and `card_statements_path` never render any of the
  # `leaks` strings even when correctly scoped — the reserved-category names are
  # the fixed "outros" / "cartão de crédito" every person gets, and a statement
  # list prints only the visited card's own name and numeric totals, never a
  # category, income or expense name. A `leaks.each { not_to include }` sweep
  # against either page would pass whether or not scoping worked, so each of
  # these two gets its own assertion on the thing that page could actually get
  # wrong.
  it "keeps another person's reserved-category records off the settings form (AC 5)" do
    get edit_settings_path
    expect(response).to have_http_status(:ok), "#{edit_settings_path} did not render"

    # The rename form's action embeds the category id — Task 5 made the reserved
    # pair unique per user (uniqueness: { scope: :user_id }) even though the two
    # names collide across every person — so a scoping bug shows up as a foreign
    # id in the form, never as a foreign name.
    rendered_ids = response.body.scan(%r{/categories/(\d+)"}).flatten.map(&:to_i)
    their_reserved_ids = Category.unscoped.where(user_id: other.id).where.not(role: nil).pluck(:id)

    expect(rendered_ids & their_reserved_ids).to be_empty
  end

  it "keeps another person's card unreachable from this account's statement screen (AC 5)" do
    get card_statements_path(@card)
    expect(response).to have_http_status(:ok), "#{card_statements_path(@card)} did not render"

    # Nothing on this page names a category, income or expense, so the only
    # foreign thing it could expose is a link to the other person's own card.
    expect(response.body).not_to match(%r{/cards/#{their[:card].id}(["/])})
  end

  it "keeps the month's figures free of the other person's money (AC 5)" do
    get root_path(month: "2026-03")

    # 500.000 income − 100.000 debit = 400.000. The other person's 900.000 income
    # and 700.000 expense must not appear in either balance.
    expect(response.body).to include("R$ 4.000,00")
    expect(response.body).not_to include("R$ 9.000,00")
  end

  it "says another person's expense no longer exists (AC 6)" do
    get edit_expense_path(their[:expense])

    expect(response).to redirect_to(root_path)
    follow_redirect!
    # ExpensesController#record_not_found appends its own explanation about
    # installments, so match the sentence both handlers share.
    expect(response.body).to include("Este registro não existe mais")
  end

  it "says another person's card no longer exists (AC 6)" do
    get edit_card_path(their[:card])

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Este registro não existe mais.")
  end

  it "keeps two cards with the same name and different closing days independent" do
    nubank = create_card!(name: "Nubank", closing_day: 5, due_day: 12)
    Expense.create!(name: "mercado-cartão", amount_cents: 30_000, date: Date.new(2026, 3, 4),
                    payment_method: "credit", card: nubank, category: @mercado)
    theirs = as(other) do
      card = create_card!(name: "Nubank", closing_day: 25, due_day: 2)
      Expense.create!(name: "farmácia-cartão", amount_cents: 50_000, date: Date.new(2026, 3, 24),
                      payment_method: "credit", card:, category: their[:category])
      card
    end

    get card_statements_path(card_id: nubank.id)

    expect(response.body).to include("R$ 300,00")
    expect(response.body).not_to include("R$ 500,00")

    get card_statements_path(theirs)
    expect(response).to redirect_to(root_path)
  end

  it "opens a ?month= link copied from another account on this account's month" do
    get root_path(month: "2026-03")

    expect(response.body).to include("R$ 4.000,00")
    leaks.each { |leak| expect(response.body).not_to include(leak) }
  end

  # Every other example here asserts what the signed-in person can READ. This
  # one asserts what a freshly created record is STAMPED with — nothing else
  # in the suite checks a new row's `user_id` against the raw table.
  #
  # Verified (per the review that requested this example) that this does NOT
  # single out `belongs_to :user, default:` the way it set out to: with that
  # option deleted from `OwnedByUser`, this example still passes, because
  # `default_scope { where(user_id: Current.user.id) }` is itself an equality
  # condition, and Rails derives `.new`'s default attributes from exactly that
  # kind of default-scope clause (`scope_for_create`) independently of
  # `belongs_to`'s own `default:`. The two mechanisms currently overlap
  # completely on every owned model's create path, so `belongs_to default:` is
  # redundant there today — real, but harmless, defense in depth (it would
  # start to matter the moment `default_scope`'s clause stopped being a plain
  # equality). The example still earns its place: it is the one place that
  # would catch a stamping bug from EITHER mechanism, e.g. a callback that
  # overwrites `user_id`, or `default_scope` changing shape.
  it "stamps a newly created record with the poster's own id (AC 5)" do
    post expenses_path, params: { expense_entry: { name: "recém-criado", amount: "10,00", date: "2026-03-15",
                                                    category_id: @mercado.id, payment_method: "debit" } }

    # `unscoped`, not the default-scoped finder: a `belongs_to default:` bug
    # that stamps the wrong person would still satisfy a scoped lookup as long
    # as it wrote the signed-in person's own id, but this must survive that
    # bug being reintroduced, so it reads the raw row instead.
    expense = Expense.unscoped.find_by!(name: "recém-criado")
    expect(expense.user_id).to eq(current_user.id)
  end
end
