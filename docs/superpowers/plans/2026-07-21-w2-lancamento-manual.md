# W2 Lançamento Manual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** First UI layer over the W1 budgeting engine: setup, home estrutural, CRUD de cartões/categorias e lançamento de ganhos/gastos (incl. parcelado e fluxo em lote de exclusão de cartão).

**Architecture:** Classic Rails REST controllers with server-rendered ERB + Tailwind; Turbo default navigation; Stimulus only for the FAB and the expense form's conditional fields. All financial rules come from the existing `Budgeting::` engine — the UI never computes statements, balances or months. The only new intelligence is the `ExpenseEntry` form object (avulso vs. parcelado) and a `Budgeting::MonthEntries` read helper.

**Tech Stack:** Rails 8.1, PostgreSQL, Hotwire (turbo-rails/stimulus-rails/importmap), Propshaft, tailwindcss-rails (new), RSpec + Capybara/selenium-webdriver (new, system specs).

## Global Constraints

- All UI copy in Portuguese (pt-BR), matching the story's wording ("outros", "cartão de crédito", "saldo do mês anterior", "saldo inicial").
- Money is always integer cents in the DB; UI uses BRL format "1.234,56" via `BrlMoney`.
- The UI never decides fatura/mês: attribution, balances and competence come only from `Budgeting::*` modules.
- Reserved categories: role `"others"` (default for uncategorized) and `"credit_card"` (fatura payment); renameable, never deletable (model already enforces).
- Destructive actions (parcelado inteiro, categoria com gastos, lote de cartão) always confirm with explicit impact text.
- FAB present on every screen, bottom-right, never covering content (`pb-24` on body).
- Existing model validations are the source of truth; controllers/forms surface them, never duplicate divergent rules.
- Tests: RSpec; no FactoryBot (project uses direct `create!` — keep it); spec helpers live in `spec/support/`.
- Run `bin/rspec` (or `bundle exec rspec`) — never `rails test`.

**Engine interfaces used (already exist, do not reimplement):**
- `Setting.instance` → `Setting` or nil; fields `first_month:Date`, `initial_balance_cents:Integer`.
- `Budgeting::BalanceChain.carried_into(month:)` → Integer cents.
- `Budgeting::Competence.month_of(expense)` → Date (beginning of month).
- `Budgeting::Schedule.for(card:, date:)` → Data with `closing_day`, `due_day`, `valid_from`.
- `Budgeting::StatementSet.statement_of(expense)` → `Budgeting::Statement` (has `effective_due`).
- `InstallmentPurchase` `after_create` generates its `expenses` via `Budgeting::InstallmentSplit`.
- `Expense::PAYMENT_METHODS = %w[credit debit cash]`.

---

### Task 1: Infra — Tailwind, gems, rotas, layout, setup guiado

**Files:**
- Modify: `Gemfile`
- Modify: `config/routes.rb`
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/controllers/application_controller.rb`
- Create: `app/controllers/setup_controller.rb`
- Create: `app/controllers/home_controller.rb`
- Create: `app/views/setup/new.html.erb`
- Create: `app/views/home/show.html.erb` (placeholder; Task 9 replaces)
- Create: `app/views/shared/_fab.html.erb`
- Create: `app/views/shared/_errors.html.erb`
- Create: `app/javascript/controllers/fab_controller.js`
- Create: `spec/support/setup_helpers.rb`
- Test: `spec/requests/setup_spec.rb`

**Interfaces:**
- Consumes: `Setting`, `Category` (motor).
- Produces: `ApplicationController#require_setup` (before_action, global), `ApplicationController#current_month` → Date (helper_method; reads `params[:month]` "YYYY-MM", clamps to `>= Setting.instance.first_month`, defaults to `Date.current.beginning_of_month`); routes `root/setup/settings/cards(+migration)/categories/incomes/expenses`; spec helpers `create_setting!`, `create_reserved_categories!`, `create_card!`; partials `shared/errors` (local: `model`) and `shared/fab`.

- [ ] **Step 1: Add gems and install Tailwind**

```bash
bundle add tailwindcss-rails
bundle add capybara selenium-webdriver --group test
bin/rails tailwindcss:install
```

Expected: `app/assets/tailwind/application.css`, `Procfile.dev`, `bin/dev` created; layout gets `stylesheet_link_tag "tailwind"` (installer does it — verify it's inside `<head>`).

- [ ] **Step 2: Write failing request spec for setup flow**

```ruby
# spec/requests/setup_spec.rb
require "rails_helper"

RSpec.describe "Setup", type: :request do
  it "redirects any page to setup when there is no Setting" do
    get root_path
    expect(response).to redirect_to(setup_path)
  end

  it "creates the Setting and the reserved categories" do
    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "1.234,56" } }
    expect(response).to redirect_to(root_path)
    expect(Setting.instance.first_month).to eq Date.new(2026, 3, 1)
    expect(Setting.instance.initial_balance_cents).to eq 123_456
    expect(Category.find_by(role: "others").name).to eq "outros"
    expect(Category.find_by(role: "credit_card").name).to eq "cartão de crédito"
  end

  it "re-renders with errors on invalid input" do
    post setup_path, params: { setup: { first_month: "", initial_balance: "0,00" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "redirects setup back to home when already configured" do
    Setting.create!(first_month: Date.new(2026, 3, 1))
    get setup_path
    expect(response).to redirect_to(root_path)
  end
end
```

Also create the shared helpers (used from Task 2 on):

```ruby
# spec/support/setup_helpers.rb
module SetupHelpers
  def create_setting!(first_month: Date.new(2026, 3, 1), initial_balance_cents: 0)
    Setting.create!(first_month:, initial_balance_cents:)
  end

  def create_reserved_categories!
    [Category.find_or_create_by!(role: "others") { |c| c.name = "outros" },
     Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" }]
  end

  def create_card!(name: "Azul", closing_day: 5, due_day: 12, valid_from: Date.new(2026, 3, 1))
    card = Card.create!(name:)
    card.card_schedules.create!(closing_day:, due_day:, valid_from:)
    card
  end
end

RSpec.configure { |config| config.include SetupHelpers }
```

- [ ] **Step 3: Run spec, verify failure**

Run: `bin/rspec spec/requests/setup_spec.rb`
Expected: FAIL — `undefined local variable or method 'setup_path'` / routing errors.

- [ ] **Step 4: Implement routes, controllers, layout**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "home#show"
  get  "setup", to: "setup#new"
  post "setup", to: "setup#create"
  resource :settings, only: %i[edit update]
  resources :cards, except: :show do
    resource :migration, only: %i[new create], controller: "card_migrations"
  end
  resources :categories
  resources :incomes, except: :show
  resources :expenses, except: :show
end
```

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :require_setup
  helper_method :current_month

  private

  def require_setup
    redirect_to setup_path if Setting.instance.nil?
  end

  def current_month
    @current_month ||= begin
      month = begin
        Date.strptime(params[:month].to_s, "%Y-%m")
      rescue ArgumentError
        Date.current
      end.beginning_of_month
      first = Setting.instance&.first_month
      first && month < first ? first : month
    end
  end
end
```

```ruby
# app/controllers/setup_controller.rb
class SetupController < ApplicationController
  skip_before_action :require_setup
  before_action { redirect_to root_path if Setting.instance }

  def new
    @setting = Setting.new(first_month: Date.current.beginning_of_month)
  end

  def create
    @setting = Setting.new(first_month: parse_month(params[:setup][:first_month]),
                           initial_balance_cents: BrlMoney.parse(params[:setup][:initial_balance]) || 0)
    if @setting.save
      Category.find_or_create_by!(role: "others") { |c| c.name = "outros" }
      Category.find_or_create_by!(role: "credit_card") { |c| c.name = "cartão de crédito" }
      redirect_to root_path, notice: "Tudo pronto — pode começar a lançar."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def parse_month(text)
    Date.strptime(text.to_s, "%Y-%m")
  rescue ArgumentError
    nil
  end
end
```

Note: `BrlMoney` arrives in Task 2. To keep Task 1 self-contained, create it here already (Task 2 then only adds `format` + specs) — minimal version:

```ruby
# app/lib/brl_money.rb
module BrlMoney
  module_function

  # "1.234,56" | "1234,56" | "-50" | "R$ 900" -> integer cents; nil se inválido.
  def parse(text)
    normalized = text.to_s.gsub(/[R$\s.]/, "").tr(",", ".")
    return nil unless normalized.match?(/\A-?\d+(\.\d{1,2})?\z/)
    (BigDecimal(normalized) * 100).to_i
  end
end
```

Add `require "bigdecimal"` at the top of the file.

```ruby
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  def show
  end
end
```

```erb
<%# app/views/home/show.html.erb — placeholder; Task 9 substitui %>
<h1 class="text-lg font-semibold">Início</h1>
```

```erb
<%# app/views/shared/_errors.html.erb %>
<% if model.errors.any? %>
  <div class="bg-red-50 border border-red-200 text-red-700 rounded p-3 mb-4 text-sm">
    <ul class="list-disc list-inside">
      <% model.errors.full_messages.each do |message| %>
        <li><%= message %></li>
      <% end %>
    </ul>
  </div>
<% end %>
```

```erb
<%# app/views/shared/_fab.html.erb %>
<div data-controller="fab" class="fixed bottom-6 right-6 z-10 flex flex-col items-end gap-2">
  <div data-fab-target="menu" hidden class="flex flex-col items-end gap-2">
    <%= link_to "ganho", new_income_path,
        class: "bg-emerald-600 text-white rounded-full px-4 py-2 shadow text-sm" %>
    <%= link_to "gasto", new_expense_path,
        class: "bg-rose-600 text-white rounded-full px-4 py-2 shadow text-sm" %>
  </div>
  <button type="button" data-action="fab#toggle" aria-label="Lançar"
          class="bg-blue-600 text-white rounded-full w-14 h-14 text-2xl shadow-lg">+</button>
</div>
```

```javascript
// app/javascript/controllers/fab_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  toggle() {
    this.menuTarget.hidden = !this.menuTarget.hidden
  }
}
```

Layout body (replace `<body>` block; keep existing `<head>`):

```erb
  <body class="min-h-screen bg-gray-50 text-gray-900 pb-24">
    <% unless Setting.instance.nil? %>
      <nav class="flex gap-4 px-4 py-3 border-b bg-white text-sm overflow-x-auto">
        <%= link_to "Início", root_path %>
        <%= link_to "Gastos", expenses_path %>
        <%= link_to "Ganhos", incomes_path %>
        <%= link_to "Cartões", cards_path %>
        <%= link_to "Categorias", categories_path %>
        <%= link_to "Config", edit_settings_path %>
      </nav>
    <% end %>
    <% if notice %><p class="bg-emerald-50 text-emerald-800 px-4 py-2 text-sm"><%= notice %></p><% end %>
    <% if alert %><p class="bg-red-50 text-red-800 px-4 py-2 text-sm"><%= alert %></p><% end %>
    <main class="p-4 max-w-xl mx-auto"><%= yield %></main>
    <%= render "shared/fab" unless Setting.instance.nil? %>
  </body>
```

```erb
<%# app/views/setup/new.html.erb %>
<h1 class="text-lg font-semibold mb-4">Primeiro acesso</h1>
<p class="text-sm text-gray-600 mb-4">Defina quando sua linha do tempo começa e com quanto.</p>
<%= form_with url: setup_path, scope: :setup, method: :post, class: "space-y-4" do |f| %>
  <%= render "shared/errors", model: @setting %>
  <div>
    <%= f.label :first_month, "Primeiro mês", class: "block text-sm mb-1" %>
    <%= f.month_field :first_month, value: @setting.first_month&.strftime("%Y-%m"), class: "border rounded p-2 w-full" %>
  </div>
  <div>
    <%= f.label :initial_balance, "Saldo inicial (R$)", class: "block text-sm mb-1" %>
    <%= f.text_field :initial_balance, value: "0,00", inputmode: "decimal", class: "border rounded p-2 w-full" %>
  </div>
  <%= f.submit "Começar", class: "bg-blue-600 text-white rounded px-4 py-2" %>
<% end %>
```

- [ ] **Step 5: Run spec, verify pass**

Run: `bin/rspec spec/requests/setup_spec.rb`
Expected: 4 examples, 0 failures. Also run `bin/rspec` (whole suite) — motor specs must stay green (the new `before_action :require_setup` does not touch models).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add Tailwind, global layout with FAB, and guided setup flow"
```

---

### Task 2: BrlMoney completo + helper `brl`

**Files:**
- Modify: `app/lib/brl_money.rb`
- Modify: `app/helpers/application_helper.rb`
- Test: `spec/lib/brl_money_spec.rb`

**Interfaces:**
- Produces: `BrlMoney.parse(text) → Integer|nil` (cents), `BrlMoney.format(cents) → String` ("1.234,56"), helper `brl(cents) → "R$ 1.234,56"`. All later tasks use these for money display/input.

- [ ] **Step 1: Write failing spec**

```ruby
# spec/lib/brl_money_spec.rb
require "rails_helper"

RSpec.describe BrlMoney do
  describe ".parse" do
    it { expect(BrlMoney.parse("1.234,56")).to eq 123_456 }
    it { expect(BrlMoney.parse("900")).to eq 90_000 }
    it { expect(BrlMoney.parse("R$ 50,5")).to eq 5_050 }
    it { expect(BrlMoney.parse("-12,34")).to eq(-1_234) }
    it { expect(BrlMoney.parse("abc")).to be_nil }
    it { expect(BrlMoney.parse("")).to be_nil }
    it { expect(BrlMoney.parse(nil)).to be_nil }
  end

  describe ".format" do
    it { expect(BrlMoney.format(123_456)).to eq "1.234,56" }
    it { expect(BrlMoney.format(0)).to eq "0,00" }
    it { expect(BrlMoney.format(-1_234)).to eq "-12,34" }
    it { expect(BrlMoney.format(100_000_000)).to eq "1.000.000,00" }
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/lib/brl_money_spec.rb`
Expected: FAIL — `.format` undefined (parse examples pass from Task 1).

- [ ] **Step 3: Implement**

```ruby
# app/lib/brl_money.rb
require "bigdecimal"

module BrlMoney
  module_function

  # "1.234,56" | "1234,56" | "-50" | "R$ 900" -> integer cents; nil se inválido.
  def parse(text)
    normalized = text.to_s.gsub(/[R$\s.]/, "").tr(",", ".")
    return nil unless normalized.match?(/\A-?\d+(\.\d{1,2})?\z/)
    (BigDecimal(normalized) * 100).to_i
  end

  def format(cents)
    sign = cents.negative? ? "-" : ""
    reais, centavos = cents.abs.divmod(100)
    "#{sign}#{reais.to_s.gsub(/(\d)(?=(\d{3})+\z)/, '\1.')},#{centavos.to_s.rjust(2, '0')}"
  end
end
```

```ruby
# app/helpers/application_helper.rb
module ApplicationHelper
  def brl(cents)
    "R$ #{BrlMoney.format(cents)}"
  end
end
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/lib/brl_money_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/lib/brl_money.rb app/helpers/application_helper.rb spec/lib/brl_money_spec.rb
git commit -m "feat: BRL money parsing/formatting and brl view helper"
```

---

### Task 3: CRUD de cartões (com vigência de dias)

**Files:**
- Create: `app/controllers/cards_controller.rb`
- Create: `app/views/cards/index.html.erb`, `app/views/cards/new.html.erb`, `app/views/cards/edit.html.erb`, `app/views/cards/_form.html.erb`
- Test: `spec/requests/cards_spec.rb`

**Interfaces:**
- Consumes: `Budgeting::Schedule.for(card:, date:)`, `Card`, `CardSchedule`, spec helpers from Task 1.
- Produces: routes `cards_path` etc. used by nav/FAB flows; `cards#destroy` redirects to `new_card_migration_path(card)` when card has expenses/purchases (Task 10 implements that flow).

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/cards_spec.rb
require "rails_helper"

RSpec.describe "Cards", type: :request do
  before { create_setting!; create_reserved_categories! }

  it "lists cards with their current days (AC 1)" do
    create_card!(name: "Azul", closing_day: 5, due_day: 12)
    get cards_path
    expect(response.body).to include("Azul").and include("fecha dia 5").and include("vence dia 12")
  end

  it "creates a card with its first schedule from the first month (AC 1)" do
    post cards_path, params: { card: { name: "Azul", closing_day: 5, due_day: 12 } }
    card = Card.find_by!(name: "Azul")
    schedule = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 10))
    expect([schedule.closing_day, schedule.due_day]).to eq [5, 12]
    expect(schedule.valid_from).to eq Setting.instance.first_month
  end

  it "rejects invalid days" do
    post cards_path, params: { card: { name: "Azul", closing_day: 0, due_day: 12 } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "editing days creates a new schedule valid from today, keeping the old one (AC 16)" do
    card = create_card!(closing_day: 5, due_day: 12)
    patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 27 } }
    expect(card.card_schedules.count).to eq 2
    old = Budgeting::Schedule.for(card:, date: Date.new(2026, 3, 10))
    current = Budgeting::Schedule.for(card:, date: Date.current)
    expect(old.closing_day).to eq 5
    expect(current.closing_day).to eq 20
  end

  it "editing only the name does not create a schedule" do
    card = create_card!
    patch card_path(card), params: { card: { name: "Azul Infinite", closing_day: 5, due_day: 12 } }
    expect(card.reload.name).to eq "Azul Infinite"
    expect(card.card_schedules.count).to eq 1
  end

  it "editing days twice in the same day updates the same schedule row" do
    card = create_card!
    patch card_path(card), params: { card: { name: "Azul", closing_day: 20, due_day: 27 } }
    patch card_path(card), params: { card: { name: "Azul", closing_day: 21, due_day: 27 } }
    expect(card.card_schedules.count).to eq 2
    expect(Budgeting::Schedule.for(card:, date: Date.current).closing_day).to eq 21
  end

  it "destroys a card without expenses" do
    card = create_card!
    delete card_path(card)
    expect(Card.exists?(card.id)).to be false
  end

  it "redirects to the migration flow when the card has expenses (AC 17)" do
    card = create_card!
    Expense.create!(name: "mercado", amount_cents: 100, payment_method: "credit",
                    card:, category: Category.find_by!(role: "others"), date: Date.new(2026, 3, 4))
    delete card_path(card)
    expect(response).to redirect_to(new_card_migration_path(card))
    expect(Card.exists?(card.id)).to be true
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/requests/cards_spec.rb`
Expected: FAIL — `CardsController` missing.

- [ ] **Step 3: Implement controller and views**

```ruby
# app/controllers/cards_controller.rb
class CardsController < ApplicationController
  before_action :set_card, only: %i[edit update destroy]

  def index
    @cards = Card.order(:name)
  end

  def new
    @card = Card.new
    @days = {}
  end

  def create
    @card = Card.new(name: card_params[:name])
    @card.card_schedules.build(closing_day: card_params[:closing_day], due_day: card_params[:due_day],
                               valid_from: Setting.instance.first_month)
    if @card.save
      redirect_to cards_path, notice: "Cartão cadastrado."
    else
      @days = card_params.slice(:closing_day, :due_day)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    schedule = Budgeting::Schedule.for(card: @card, date: Date.current)
    @days = { closing_day: schedule.closing_day, due_day: schedule.due_day }
  end

  def update
    @card.name = card_params[:name]
    schedule = new_schedule_if_days_changed
    if [@card, *schedule].all?(&:valid?)
      ActiveRecord::Base.transaction { @card.save!; schedule&.save! }
      redirect_to cards_path, notice: "Cartão atualizado."
    else
      @days = card_params.slice(:closing_day, :due_day)
      @card.errors.merge!(schedule.errors) if schedule
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @card.expenses.exists? || @card.installment_purchases.exists?
      redirect_to new_card_migration_path(@card)
    else
      @card.destroy
      redirect_to cards_path, notice: "Cartão excluído."
    end
  end

  private

  def set_card = @card = Card.find(params[:id])

  def card_params = params.require(:card).permit(:name, :closing_day, :due_day)

  # Editar dias nunca altera vigência antiga: cria (ou reusa, se de hoje)
  # uma vigência a partir de hoje — faturas fechadas seguem as antigas.
  def new_schedule_if_days_changed
    current = Budgeting::Schedule.for(card: @card, date: Date.current)
    wanted = [card_params[:closing_day].to_i, card_params[:due_day].to_i]
    return nil if [current.closing_day, current.due_day] == wanted

    row = @card.card_schedules.find_or_initialize_by(valid_from: Date.current)
    row.assign_attributes(closing_day: wanted[0], due_day: wanted[1])
    row
  end
end
```

```erb
<%# app/views/cards/_form.html.erb — locals: card:, days:, url: %>
<%= form_with model: card, url: url, class: "space-y-4" do |f| %>
  <%= render "shared/errors", model: card %>
  <div>
    <%= f.label :name, "Nome", class: "block text-sm mb-1" %>
    <%= f.text_field :name, class: "border rounded p-2 w-full" %>
  </div>
  <div class="flex gap-4">
    <div>
      <%= f.label :closing_day, "Dia de fechamento", class: "block text-sm mb-1" %>
      <%= f.number_field :closing_day, value: days[:closing_day], min: 1, max: 31, class: "border rounded p-2 w-24" %>
    </div>
    <div>
      <%= f.label :due_day, "Dia de vencimento", class: "block text-sm mb-1" %>
      <%= f.number_field :due_day, value: days[:due_day], min: 1, max: 31, class: "border rounded p-2 w-24" %>
    </div>
  </div>
  <%= f.submit "Salvar", class: "bg-blue-600 text-white rounded px-4 py-2" %>
<% end %>
```

```erb
<%# app/views/cards/index.html.erb %>
<div class="flex items-center justify-between mb-4">
  <h1 class="text-lg font-semibold">Cartões</h1>
  <%= link_to "novo cartão", new_card_path, class: "text-blue-600 text-sm" %>
</div>
<ul class="divide-y bg-white rounded border">
  <% @cards.each do |card| %>
    <% schedule = Budgeting::Schedule.for(card:, date: Date.current) %>
    <li class="p-3 flex items-center justify-between">
      <div>
        <p class="font-medium"><%= card.name %></p>
        <p class="text-sm text-gray-500">fecha dia <%= schedule.closing_day %> · vence dia <%= schedule.due_day %></p>
      </div>
      <div class="flex gap-3 text-sm">
        <%= link_to "editar", edit_card_path(card), class: "text-blue-600" %>
        <%= button_to "excluir", card_path(card), method: :delete, class: "text-red-600",
              data: { turbo_confirm: "Excluir o cartão #{card.name}?" } %>
      </div>
    </li>
  <% end %>
  <% if @cards.empty? %><li class="p-3 text-sm text-gray-500">Nenhum cartão ainda.</li><% end %>
</ul>
```

```erb
<%# app/views/cards/new.html.erb %>
<h1 class="text-lg font-semibold mb-4">Novo cartão</h1>
<%= render "form", card: @card, days: @days, url: cards_path %>
```

```erb
<%# app/views/cards/edit.html.erb %>
<h1 class="text-lg font-semibold mb-4">Editar cartão</h1>
<%= render "form", card: @card, days: @days, url: card_path(@card) %>
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/requests/cards_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/cards_controller.rb app/views/cards spec/requests/cards_spec.rb
git commit -m "feat: cards CRUD with effective-dated schedule edits"
```

---

### Task 4: Budgeting::MonthEntries (gastos de um mês, por competência)

**Files:**
- Create: `app/models/budgeting/month_entries.rb`
- Test: `spec/models/budgeting/month_entries_spec.rb`

**Interfaces:**
- Consumes: `Budgeting::Competence.month_of(expense)`.
- Produces: `Budgeting::MonthEntries.expenses(month:, category: nil) → Array<Expense>` — dated expenses of the calendar month plus installment expenses whose competence month matches; sorted by date (installments use the month itself), then name. Used by expenses#index, categories#show.

- [ ] **Step 1: Write failing spec**

```ruby
# spec/models/budgeting/month_entries_spec.rb
require "rails_helper"

RSpec.describe Budgeting::MonthEntries do
  before do
    create_setting!
    create_reserved_categories!
  end

  let(:others) { Category.find_by!(role: "others") }
  let(:march) { Date.new(2026, 3, 1) }

  it "returns dated expenses of the month and installments by competence" do
    card = create_card!
    Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "debit",
                    category: others, date: Date.new(2026, 3, 10))
    Expense.create!(name: "abril", amount_cents: 1_000, payment_method: "cash",
                    category: others, date: Date.new(2026, 4, 2))
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))

    names = described_class.expenses(month: march).map(&:name)
    expect(names).to include("padaria", "sofá 1/10")
    expect(names).not_to include("abril", "sofá 2/10")
  end

  it "filters by category" do
    mercado = Category.create!(name: "mercado")
    Expense.create!(name: "feira", amount_cents: 2_000, payment_method: "cash",
                    category: mercado, date: Date.new(2026, 3, 5))
    Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "debit",
                    category: others, date: Date.new(2026, 3, 10))

    names = described_class.expenses(month: march, category: mercado).map(&:name)
    expect(names).to eq ["feira"]
  end

  it "sorts by date then name" do
    Expense.create!(name: "b", amount_cents: 100, payment_method: "cash", category: others, date: Date.new(2026, 3, 20))
    Expense.create!(name: "a", amount_cents: 100, payment_method: "cash", category: others, date: Date.new(2026, 3, 5))
    expect(described_class.expenses(month: march).map(&:name)).to eq %w[a b]
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/models/budgeting/month_entries_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 3: Implement**

```ruby
# app/models/budgeting/month_entries.rb
module Budgeting
  # Gastos exibíveis de um mês: os com data dentro do mês civil + as
  # parcelas cuja competência cai no mês. Só leitura, para as listas.
  module MonthEntries
    module_function

    def expenses(month:, category: nil)
      target = month.beginning_of_month
      dated = Expense.where(date: target.all_month).includes(:category, :card)
      dated = dated.where(category:) if category
      undated = Expense.where(date: nil).includes(:installment_purchase, :category, :card)
      undated = undated.where(category:) if category
      undated = undated.select { |expense| Competence.month_of(expense) == target }
      (dated.to_a + undated).sort_by { |expense| [expense.date || target, expense.name] }
    end
  end
end
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/models/budgeting/month_entries_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/models/budgeting/month_entries.rb spec/models/budgeting/month_entries_spec.rb
git commit -m "feat: Budgeting::MonthEntries month listing by competence"
```

---

### Task 5: ExpenseEntry form object + regeneração de parcelado

**Files:**
- Create: `app/models/expense_entry.rb`
- Modify: `app/models/installment_purchase.rb` (add public `regenerate_installments!`)
- Test: `spec/models/expense_entry_spec.rb`

**Interfaces:**
- Consumes: `BrlMoney`, `Expense`, `InstallmentPurchase`, `Category.find_by!(role: "others")`.
- Produces:
  - `ExpenseEntry.new(name:, amount:, date:, category_id:, payment_method:, card_id:, installment:, installments_count:, first_installment:)` — all strings from params.
  - `#save → bool` (creates `Expense` or, se `installment == "1"`, `InstallmentPurchase`); `#record` → the created/updated model.
  - `#update(source) → bool` — source is `Expense` (avulso) or `InstallmentPurchase` (série inteira recalculada).
  - `ExpenseEntry.from(source) → ExpenseEntry` prefilled for edit forms.
  - `#installment? → bool`.
  - `InstallmentPurchase#regenerate_installments!` — destroys and regenerates the series.

- [ ] **Step 1: Write failing spec**

```ruby
# spec/models/expense_entry_spec.rb
require "rails_helper"

RSpec.describe ExpenseEntry do
  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }
  let(:card) { create_card! }

  def entry(overrides = {})
    described_class.new({ name: "padaria", amount: "50,00", date: "2026-03-10",
                          category_id: others.id.to_s, payment_method: "debit" }.merge(overrides))
  end

  describe "#save (avulso)" do
    it "creates a debit expense (AC 4)" do
      e = entry
      expect(e.save).to be true
      expect(e.record).to be_a(Expense)
      expect(e.record.amount_cents).to eq 5_000
    end

    it "defaults to the reserved 'others' category when blank (AC 12)" do
      e = entry(category_id: "")
      expect(e.save).to be true
      expect(e.record.category).to eq others
    end

    it "creates a credit expense bound to the card (AC 5)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, name: "mercado", amount: "200,00", date: "2026-03-04")
      expect(e.save).to be true
      statement = Budgeting::StatementSet.statement_of(e.record)
      expect(statement.effective_due).to eq Date.new(2026, 3, 12)
    end

    it "rejects unparseable and non-positive amounts (AC 14)" do
      expect(entry(amount: "abc").save).to be false
      expect(entry(amount: "0,00").save).to be false
      expect(entry(amount: "-5").save).to be false
    end

    it "surfaces model errors (credit without card, date before first month) (AC 13/19)" do
      e = entry(payment_method: "credit", card_id: "")
      expect(e.save).to be false
      expect(e.errors[:card]).to be_present

      e = entry(date: "2026-02-10")
      expect(e.save).to be false
      expect(e.errors[:date]).to be_present
    end
  end

  describe "#save (parcelado)" do
    it "creates the whole series at once (AC 6)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1",
                name: "sofá", amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      expect(e.save).to be true
      expect(e.record).to be_a(InstallmentPurchase)
      expect(e.record.expenses.order(:installment_number).map(&:name).first).to eq "sofá 1/10"
      expect(e.record.expenses.count).to eq 10
      expect(e.record.expenses.sum(:amount_cents)).to eq 100_000
    end

    it "puts the cents remainder on the first created installment (AC 7)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1",
                amount: "100,00", installments_count: "3", date: "2026-03-10")
      e.save
      expect(e.record.expenses.order(:installment_number).map(&:amount_cents)).to eq [3_334, 3_333, 3_333]
    end

    it "starts at the given first installment (AC 8)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", first_installment: "4", date: "2026-03-10")
      e.save
      expect(e.record.expenses.order(:installment_number).map(&:installment_number)).to eq (4..10).to_a
    end
  end

  describe "#update" do
    it "updates a plain expense" do
      e = entry
      e.save
      updated = entry(name: "café", amount: "10,00")
      expect(updated.update(e.record)).to be true
      expect(e.record.reload.name).to eq "café"
    end

    it "recalculates the whole series on purchase edit (AC 9)" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      purchase = e.record
      updated = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                      amount: "500,00", installments_count: "5", date: "2026-03-10")
      expect(updated.update(purchase)).to be true
      expect(purchase.reload.expenses.count).to eq 5
      expect(purchase.expenses.sum(:amount_cents)).to eq 50_000
    end

    it "keeps the series intact when the purchase edit is invalid" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      bad = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "",
                  amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      expect(bad.update(e.record.reload)).to be false
      expect(e.record.reload.expenses.count).to eq 10
    end
  end

  describe ".from" do
    it "prefills from a purchase" do
      e = entry(payment_method: "credit", card_id: card.id.to_s, installment: "1", name: "sofá",
                amount: "1.000,00", installments_count: "10", date: "2026-03-10")
      e.save
      prefilled = described_class.from(e.record)
      expect(prefilled.amount).to eq "1.000,00"
      expect(prefilled.installment?).to be true
    end
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/models/expense_entry_spec.rb`
Expected: FAIL — uninitialized constant ExpenseEntry.

- [ ] **Step 3: Implement**

Add to `InstallmentPurchase` (below validations, above `private`):

```ruby
  # Recalcula a série inteira após edição — apaga e regenera pelo motor.
  def regenerate_installments!
    expenses.destroy_all
    generate_installments
  end
```

```ruby
# app/models/expense_entry.rb
# Form object do lançamento de gasto: decide entre Expense avulso e
# InstallmentPurchase (parcelado) e traduz valor BRL -> centavos. Toda regra
# financeira permanece nos models/motor; aqui só orquestração e parse.
class ExpenseEntry
  include ActiveModel::Model

  attr_accessor :name, :amount, :date, :category_id, :payment_method,
                :card_id, :installment, :installments_count, :first_installment
  attr_reader :record

  validate :amount_must_parse

  def self.from(source)
    case source
    when InstallmentPurchase
      new(name: source.name, amount: BrlMoney.format(source.total_cents), date: source.date,
          category_id: source.category_id, payment_method: "credit", card_id: source.card_id,
          installment: "1", installments_count: source.installments_count,
          first_installment: source.first_installment)
    else
      new(name: source.name, amount: BrlMoney.format(source.amount_cents), date: source.date,
          category_id: source.category_id, payment_method: source.payment_method,
          card_id: source.card_id)
    end
  end

  def installment? = installment.to_s == "1"

  def save
    return false unless valid?
    @record = installment? ? build_purchase : Expense.new(expense_attributes)
    persist(@record)
  end

  def update(source)
    return false unless valid?
    @record = source
    case source
    when InstallmentPurchase then update_purchase(source)
    else
      source.assign_attributes(expense_attributes)
      persist(source)
    end
  end

  private

  def amount_cents = BrlMoney.parse(amount)

  def amount_must_parse
    errors.add(:amount, "não é um valor válido") if amount_cents.nil? || amount_cents <= 0
  end

  def category
    category_id.present? ? Category.find(category_id) : Category.find_by!(role: "others")
  end

  def expense_attributes
    { name:, amount_cents:, date: date.presence, category:, payment_method:,
      card_id: payment_method == "credit" ? card_id.presence : nil }
  end

  def build_purchase
    InstallmentPurchase.new(name:, total_cents: amount_cents, date: date.presence, category:,
                            card_id: card_id.presence, installments_count:,
                            first_installment: first_installment.presence || 1)
  end

  def update_purchase(purchase)
    purchase.assign_attributes(name:, total_cents: amount_cents, date: date.presence, category:,
                               card_id: card_id.presence, installments_count:,
                               first_installment: first_installment.presence || 1)
    ok = false
    ActiveRecord::Base.transaction do
      ok = persist(purchase)
      purchase.regenerate_installments! if ok
      raise ActiveRecord::Rollback unless ok
    end
    purchase.reload unless ok
    ok
  end

  def persist(model)
    return true if model.save
    model.errors.each { |error| errors.import(error) }
    false
  end
end
```


- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/models/expense_entry_spec.rb spec/models/installment_purchase_spec.rb`
Expected: all pass (existing purchase specs stay green).

- [ ] **Step 5: Commit**

```bash
git add app/models/expense_entry.rb app/models/installment_purchase.rb spec/models/expense_entry_spec.rb
git commit -m "feat: ExpenseEntry form object with installment series regeneration"
```

---

### Task 6: Gastos — controller, views e Stimulus do form

**Files:**
- Create: `app/controllers/expenses_controller.rb`
- Create: `app/views/expenses/index.html.erb`, `app/views/expenses/new.html.erb`, `app/views/expenses/edit.html.erb`, `app/views/expenses/_form.html.erb`
- Create: `app/views/shared/_month_nav.html.erb`
- Create: `app/javascript/controllers/expense_form_controller.js`
- Test: `spec/requests/expenses_spec.rb`

**Interfaces:**
- Consumes: `ExpenseEntry` (Task 5), `Budgeting::MonthEntries.expenses(month:, category:)` (Task 4), `current_month` (Task 1), `brl` (Task 2).
- Produces: partial `shared/month_nav` (locals: `path_helper` — a lambda taking `month:` keyword and returning a path) reused by incomes/home/categories; expense row rendering pattern reused in categories#show.

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/expenses_spec.rb
require "rails_helper"

RSpec.describe "Expenses", type: :request do
  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }
  let(:credit_card_cat) { Category.find_by!(role: "credit_card") }
  let(:card) { create_card! }

  it "lists the month's expenses with method label (AC 4)" do
    Expense.create!(name: "padaria", amount_cents: 5_000, payment_method: "debit",
                    category: others, date: Date.new(2026, 3, 10))
    get expenses_path(month: "2026-03")
    expect(response.body).to include("padaria").and include("débito")
  end

  it "creates a debit expense (AC 4)" do
    post expenses_path, params: { expense_entry: { name: "padaria", amount: "50,00", date: "2026-03-10",
                                                   category_id: others.id, payment_method: "debit" } }
    expect(Expense.find_by(name: "padaria").payment_method).to eq "debit"
  end

  it "accepts a debit expense in the credit-card category — fatura payment (AC 11)" do
    post expenses_path, params: { expense_entry: { name: "fatura azul", amount: "800,00", date: "2026-03-12",
                                                   category_id: credit_card_cat.id, payment_method: "debit" } }
    expect(Expense.find_by(name: "fatura azul").category).to eq credit_card_cat
  end

  it "rejects a credit expense in the credit-card category (AC 11, server side)" do
    post expenses_path, params: { expense_entry: { name: "x", amount: "10,00", date: "2026-03-12",
                                                   category_id: credit_card_cat.id,
                                                   payment_method: "credit", card_id: card.id } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "shows the register-a-card message on the form when there is no card (AC 13)" do
    get new_expense_path
    expect(response.body).to include("cadastre um cartão").and include(new_card_path)
  end

  it "creates an installment purchase from the same form (AC 6)" do
    post expenses_path, params: { expense_entry: { name: "sofá", amount: "1.000,00", date: "2026-03-10",
                                                   category_id: others.id, payment_method: "credit",
                                                   card_id: card.id, installment: "1", installments_count: "10" } }
    expect(InstallmentPurchase.find_by(name: "sofá").expenses.count).to eq 10
  end

  it "rejects invalid amounts with a message (AC 14)" do
    post expenses_path, params: { expense_entry: { name: "x", amount: "0,00", date: "2026-03-10",
                                                   category_id: others.id, payment_method: "cash" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
  end

  it "blocks dates before the first month (AC 19)" do
    post expenses_path, params: { expense_entry: { name: "x", amount: "10,00", date: "2026-02-10",
                                                   category_id: others.id, payment_method: "cash" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("primeiro mês")
  end

  it "moving a credit expense's date moves its statement (AC 10)" do
    expense = Expense.create!(name: "mercado", amount_cents: 20_000, payment_method: "credit",
                              card:, category: others, date: Date.new(2026, 3, 4))
    patch expense_path(expense), params: { expense_entry: { name: "mercado", amount: "200,00", date: "2026-03-06",
                                                            category_id: others.id, payment_method: "credit",
                                                            card_id: card.id } }
    expect(Budgeting::StatementSet.statement_of(expense.reload).effective_due).to eq Date.new(2026, 4, 13)
  end

  it "editing any installment edits the whole purchase (AC 9)" do
    purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                           card:, category: others, date: Date.new(2026, 3, 10))
    third = purchase.expenses.find_by!(installment_number: 3)
    get edit_expense_path(third)
    expect(response.body).to include("1.000,00")

    patch expense_path(third), params: { expense_entry: { name: "sofá", amount: "500,00", date: "2026-03-10",
                                                          category_id: others.id, payment_method: "credit",
                                                          card_id: card.id, installment: "1",
                                                          installments_count: "5" } }
    expect(purchase.reload.expenses.count).to eq 5
  end

  it "deleting any installment deletes the whole purchase (AC 9)" do
    purchase = InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                           card:, category: others, date: Date.new(2026, 3, 10))
    delete expense_path(purchase.expenses.first)
    expect(InstallmentPurchase.exists?(purchase.id)).to be false
    expect(Expense.where(name: "sofá 1/10")).to be_empty
  end

  it "deletes a plain expense" do
    expense = Expense.create!(name: "padaria", amount_cents: 100, payment_method: "cash",
                              category: others, date: Date.new(2026, 3, 10))
    delete expense_path(expense)
    expect(Expense.exists?(expense.id)).to be false
  end
end
```

Note AC 10's expected due date: cycle for a purchase on 06/03 with closing day 5 → next closing after 06/03 is 05/04; due 12/04 is a Sunday in 2026 → `Calendar.effective_due` pushes to the next business day, **13/04/2026 (Monday)**. If the assertion fails, print `Budgeting::StatementSet.statement_of(expense.reload).effective_due` and check against `Budgeting::Calendar` rules — the motor is the source of truth; adjust the expected date only with that justification.

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/requests/expenses_spec.rb`
Expected: FAIL — `ExpensesController` missing.

- [ ] **Step 3: Implement controller**

```ruby
# app/controllers/expenses_controller.rb
class ExpensesController < ApplicationController
  def index
    @expenses = Budgeting::MonthEntries.expenses(month: current_month)
  end

  def new
    @entry = ExpenseEntry.new(date: Date.current, payment_method: "debit")
  end

  def create
    @entry = ExpenseEntry.new(entry_params)
    if @entry.save
      redirect_to expenses_path(month: month_of(@entry.record)), notice: "Gasto lançado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @expense = Expense.find(params[:id])
    @entry = ExpenseEntry.from(source_for(@expense))
  end

  def update
    @expense = Expense.find(params[:id])
    @entry = ExpenseEntry.new(entry_params)
    if @entry.update(source_for(@expense))
      redirect_to expenses_path(month: month_of(@entry.record)), notice: "Gasto atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    expense = Expense.find(params[:id])
    if expense.installment?
      expense.installment_purchase.destroy
      redirect_to expenses_path, notice: "Compra parcelada excluída por inteiro."
    else
      expense.destroy
      redirect_to expenses_path, notice: "Gasto excluído."
    end
  end

  private

  def source_for(expense) = expense.installment? ? expense.installment_purchase : expense

  def month_of(record) = record.date&.strftime("%Y-%m")

  def entry_params
    params.require(:expense_entry)
          .permit(:name, :amount, :date, :category_id, :payment_method,
                  :card_id, :installment, :installments_count, :first_installment)
  end
end
```

- [ ] **Step 4: Implement views and Stimulus controller**

```erb
<%# app/views/shared/_month_nav.html.erb — locals: path_helper (lambda month: -> path) %>
<% first = Setting.instance.first_month %>
<div class="flex items-center justify-between mb-4">
  <% if current_month > first %>
    <%= link_to "‹", path_helper.call(month: (current_month << 1).strftime("%Y-%m")), class: "px-3 py-1 text-lg" %>
  <% else %>
    <span class="px-3 py-1 text-lg text-gray-300">‹</span>
  <% end %>
  <h2 class="font-medium"><%= current_month.strftime("%m/%Y") %></h2>
  <%= link_to "›", path_helper.call(month: (current_month >> 1).strftime("%Y-%m")), class: "px-3 py-1 text-lg" %>
</div>
```

(No I18n: the project has no pt-BR locale data; "03/2026" is the agreed display.)

```erb
<%# app/views/expenses/index.html.erb %>
<h1 class="text-lg font-semibold mb-2">Gastos</h1>
<%= render "shared/month_nav", path_helper: ->(month:) { expenses_path(month:) } %>
<ul class="divide-y bg-white rounded border">
  <% method_labels = { "credit" => "crédito", "debit" => "débito", "cash" => "dinheiro" } %>
  <% @expenses.each do |expense| %>
    <li class="p-3 flex items-center justify-between gap-2">
      <div>
        <p class="font-medium"><%= expense.name %></p>
        <p class="text-sm text-gray-500">
          <%= brl(expense.amount_cents) %> · <%= method_labels[expense.payment_method] %><% if expense.card %> · <%= expense.card.name %><% end %>
          · <%= expense.category.name %>
        </p>
      </div>
      <div class="flex gap-3 text-sm shrink-0">
        <%= link_to "editar", edit_expense_path(expense), class: "text-blue-600" %>
        <%= button_to "excluir", expense_path(expense), method: :delete, class: "text-red-600",
              data: { turbo_confirm: expense.installment? ?
                "Excluir remove a compra parcelada inteira (#{expense.installment_purchase.installments_count} parcelas). Confirmar?" :
                "Excluir o gasto #{expense.name}?" } %>
      </div>
    </li>
  <% end %>
  <% if @expenses.empty? %><li class="p-3 text-sm text-gray-500">Nenhum gasto neste mês.</li><% end %>
</ul>
```

```erb
<%# app/views/expenses/_form.html.erb — locals: entry:, url: %>
<%= form_with model: entry, url: url, scope: :expense_entry, class: "space-y-4",
      data: { controller: "expense-form" } do |f| %>
  <%= render "shared/errors", model: entry %>
  <div>
    <%= f.label :name, "Nome", class: "block text-sm mb-1" %>
    <%= f.text_field :name, class: "border rounded p-2 w-full" %>
  </div>
  <div>
    <%= f.label :amount, class: "block text-sm mb-1" do %><span data-expense-form-target="amountLabel">Valor (R$)</span><% end %>
    <%= f.text_field :amount, inputmode: "decimal", class: "border rounded p-2 w-full" %>
  </div>
  <div>
    <%= f.label :date, "Data", class: "block text-sm mb-1" %>
    <%= f.date_field :date, value: entry.date, class: "border rounded p-2 w-full" %>
  </div>
  <div>
    <%= f.label :category_id, "Categoria", class: "block text-sm mb-1" %>
    <%= f.select :category_id,
          Category.order(:name).map { |c| [c.name, c.id, { data: { role: c.role, expense_form_target: "categoryOption" } }] },
          {}, class: "border rounded p-2 w-full" %>
  </div>
  <fieldset>
    <legend class="text-sm mb-1">Método</legend>
    <div class="flex gap-4">
      <% { "credit" => "crédito", "debit" => "débito", "cash" => "dinheiro" }.each do |value, label| %>
        <label class="flex items-center gap-1 text-sm">
          <%= f.radio_button :payment_method, value, data: { action: "expense-form#refresh" } %> <%= label %>
        </label>
      <% end %>
    </div>
  </fieldset>
  <div data-expense-form-target="cardSection" hidden>
    <% if Card.none? %>
      <p class="text-sm bg-amber-50 border border-amber-200 rounded p-3">
        Para lançar no crédito, cadastre um cartão antes.
        <%= link_to "Cadastrar cartão", new_card_path, class: "text-blue-600 underline" %>
      </p>
    <% else %>
      <%= f.label :card_id, "Cartão", class: "block text-sm mb-1" %>
      <%= f.select :card_id, Card.order(:name).pluck(:name, :id), { include_blank: "escolha…" },
            class: "border rounded p-2 w-full" %>
    <% end %>
  </div>
  <div data-expense-form-target="installmentSection" hidden>
    <label class="flex items-center gap-2 text-sm">
      <%= f.check_box :installment, data: { action: "expense-form#refresh" } %> parcelado
    </label>
    <div data-expense-form-target="installmentFields" hidden class="flex gap-4 mt-2">
      <div>
        <%= f.label :installments_count, "Nº de parcelas", class: "block text-sm mb-1" %>
        <%= f.number_field :installments_count, min: 2, class: "border rounded p-2 w-28" %>
      </div>
      <div>
        <%= f.label :first_installment, "Parcela inicial", class: "block text-sm mb-1" %>
        <%= f.number_field :first_installment, min: 1, value: entry.first_installment || 1, class: "border rounded p-2 w-28" %>
      </div>
    </div>
  </div>
  <%= f.submit "Salvar", class: "bg-blue-600 text-white rounded px-4 py-2" %>
<% end %>
```

```erb
<%# app/views/expenses/new.html.erb %>
<h1 class="text-lg font-semibold mb-4">Lançar gasto</h1>
<%= render "form", entry: @entry, url: expenses_path %>
```

```erb
<%# app/views/expenses/edit.html.erb %>
<h1 class="text-lg font-semibold mb-4">Editar gasto</h1>
<% if @entry.installment? %>
  <p class="text-sm bg-amber-50 border border-amber-200 rounded p-3 mb-4">
    Este gasto é uma parcela — as alterações recalculam a compra inteira.
  </p>
<% end %>
<%= render "form", entry: @entry, url: expense_path(@expense) %>
```

```javascript
// app/javascript/controllers/expense_form_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cardSection", "installmentSection", "installmentFields", "amountLabel", "categoryOption"]

  connect() { this.refresh() }

  refresh() {
    const credit = this.method === "credit"
    this.cardSectionTarget.hidden = !credit
    this.installmentSectionTarget.hidden = !credit
    this.categoryOptionTargets.forEach(option => {
      const blocked = credit && option.dataset.role === "credit_card"
      option.disabled = blocked
      option.hidden = blocked
      if (blocked && option.selected) option.selected = false
    })
    const parcelado = credit && this.installmentCheckbox?.checked
    this.installmentFieldsTarget.hidden = !parcelado
    this.amountLabelTarget.textContent = parcelado ? "Valor total (R$)" : "Valor (R$)"
  }

  get method() {
    return this.element.querySelector('input[name="expense_entry[payment_method]"]:checked')?.value
  }

  get installmentCheckbox() {
    return this.element.querySelector('input[name="expense_entry[installment]"][type="checkbox"]')
  }
}
```

- [ ] **Step 5: Run, verify pass**

Run: `bin/rspec spec/requests/expenses_spec.rb`
Expected: all pass. If the AC 13 example fails on copy, the form's no-card message must contain the literal "cadastre um cartão" — but note it's inside the hidden `cardSection` div; the request spec checks the HTML body, which includes hidden content, so it passes.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/expenses_controller.rb app/views/expenses app/views/shared/_month_nav.html.erb app/javascript/controllers/expense_form_controller.js spec/requests/expenses_spec.rb
git commit -m "feat: expense entry screens with installment support and month list"
```

---

### Task 7: Ganhos — controller, views, linha derivada

**Files:**
- Create: `app/controllers/incomes_controller.rb`
- Create: `app/views/incomes/index.html.erb`, `app/views/incomes/new.html.erb`, `app/views/incomes/edit.html.erb`, `app/views/incomes/_form.html.erb`
- Test: `spec/requests/incomes_spec.rb`

**Interfaces:**
- Consumes: `Budgeting::BalanceChain.carried_into(month:)`, `BrlMoney`, `shared/month_nav` (Task 6), `edit_settings_path` (route from Task 1; controller lands in Task 11 — link target only).
- Produces: nothing consumed later.

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/incomes_spec.rb
require "rails_helper"

RSpec.describe "Incomes", type: :request do
  before { create_setting!(initial_balance_cents: 10_000); create_reserved_categories! }

  it "creates an income (AC 3)" do
    post incomes_path, params: { income: { name: "salário", amount: "5.000,00", date: "2026-03-01" } }
    expect(Income.find_by(name: "salário").amount_cents).to eq 500_000
  end

  it "lists the month's incomes with the derived carried balance first (AC 18)" do
    Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 4, 1))
    get incomes_path(month: "2026-04")
    expect(response.body).to include("saldo do mês anterior").and include("salário")
    expect(response.body.index("saldo do mês anterior")).to be < response.body.index("salário")
  end

  it "labels the first month's derived row as saldo inicial with a link to settings (AC 18)" do
    get incomes_path(month: "2026-03")
    expect(response.body).to include("saldo inicial").and include(edit_settings_path)
  end

  it "rejects invalid amounts (AC 14)" do
    post incomes_path, params: { income: { name: "x", amount: "0,00", date: "2026-03-01" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "blocks dates before the first month (AC 19)" do
    post incomes_path, params: { income: { name: "x", amount: "10,00", date: "2026-02-01" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("primeiro mês")
  end

  it "updates and destroys a real income" do
    income = Income.create!(name: "salário", amount_cents: 500_000, date: Date.new(2026, 3, 1))
    patch income_path(income), params: { income: { name: "salário líquido", amount: "4.800,00", date: "2026-03-01" } }
    expect(income.reload.amount_cents).to eq 480_000
    delete income_path(income)
    expect(Income.exists?(income.id)).to be false
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/requests/incomes_spec.rb`
Expected: FAIL — `IncomesController` missing.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/incomes_controller.rb
class IncomesController < ApplicationController
  before_action :set_income, only: %i[edit update destroy]

  def index
    @incomes = Income.where(date: current_month.all_month).order(:date, :name)
    @carried_cents = Budgeting::BalanceChain.carried_into(month: current_month)
    @first_month = current_month == Setting.instance.first_month
  end

  def new
    @income = Income.new(date: Date.current)
  end

  def create
    @income = Income.new(income_attributes)
    if @income.save
      redirect_to incomes_path(month: @income.date.strftime("%Y-%m")), notice: "Ganho lançado."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @income.update(income_attributes)
      redirect_to incomes_path(month: @income.date.strftime("%Y-%m")), notice: "Ganho atualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @income.destroy
    redirect_to incomes_path, notice: "Ganho excluído."
  end

  private

  def set_income = @income = Income.find(params[:id])

  def income_attributes
    permitted = params.require(:income).permit(:name, :amount, :date)
    { name: permitted[:name], date: permitted[:date], amount_cents: BrlMoney.parse(permitted[:amount]) }
  end
end
```

Note: an unparseable `amount` yields `amount_cents: nil` → the model's numericality validation reports "valor não é um número" on `amount_cents`. Good enough for AC 14; the field label in the form says "Valor (R$)".

```erb
<%# app/views/incomes/_form.html.erb — locals: income:, url: %>
<%= form_with model: income, url: url, class: "space-y-4" do |f| %>
  <%= render "shared/errors", model: income %>
  <div>
    <%= f.label :name, "Nome", class: "block text-sm mb-1" %>
    <%= f.text_field :name, class: "border rounded p-2 w-full" %>
  </div>
  <div>
    <%= f.label :amount, "Valor (R$)", class: "block text-sm mb-1" %>
    <%= f.text_field :amount, value: income.amount_cents && BrlMoney.format(income.amount_cents),
          inputmode: "decimal", class: "border rounded p-2 w-full" %>
  </div>
  <div>
    <%= f.label :date, "Data", class: "block text-sm mb-1" %>
    <%= f.date_field :date, value: income.date, class: "border rounded p-2 w-full" %>
  </div>
  <%= f.submit "Salvar", class: "bg-blue-600 text-white rounded px-4 py-2" %>
<% end %>
```

```erb
<%# app/views/incomes/index.html.erb %>
<h1 class="text-lg font-semibold mb-2">Ganhos</h1>
<%= render "shared/month_nav", path_helper: ->(month:) { incomes_path(month:) } %>
<ul class="divide-y bg-white rounded border">
  <li class="p-3 flex items-center justify-between bg-gray-50">
    <div>
      <p class="font-medium"><%= @first_month ? "saldo inicial" : "saldo do mês anterior" %></p>
      <p class="text-sm text-gray-500"><%= brl(@carried_cents) %> · derivado</p>
    </div>
    <% if @first_month %>
      <%= link_to "editar", edit_settings_path, class: "text-blue-600 text-sm" %>
    <% end %>
  </li>
  <% @incomes.each do |income| %>
    <li class="p-3 flex items-center justify-between">
      <div>
        <p class="font-medium"><%= income.name %></p>
        <p class="text-sm text-gray-500"><%= brl(income.amount_cents) %> · <%= income.date.strftime("%d/%m/%Y") %></p>
      </div>
      <div class="flex gap-3 text-sm">
        <%= link_to "editar", edit_income_path(income), class: "text-blue-600" %>
        <%= button_to "excluir", income_path(income), method: :delete, class: "text-red-600",
              data: { turbo_confirm: "Excluir o ganho #{income.name}?" } %>
      </div>
    </li>
  <% end %>
  <% if @incomes.empty? %><li class="p-3 text-sm text-gray-500">Nenhum ganho lançado neste mês.</li><% end %>
</ul>
```

```erb
<%# app/views/incomes/new.html.erb %>
<h1 class="text-lg font-semibold mb-4">Lançar ganho</h1>
<%= render "form", income: @income, url: incomes_path %>
```

```erb
<%# app/views/incomes/edit.html.erb %>
<h1 class="text-lg font-semibold mb-4">Editar ganho</h1>
<%= render "form", income: @income, url: income_path(@income) %>
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/requests/incomes_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/incomes_controller.rb app/views/incomes spec/requests/incomes_spec.rb
git commit -m "feat: income screens with derived carried-balance row"
```

---

### Task 8: Categorias — CRUD, orçado do mês, exclusão com realocação

**Files:**
- Create: `app/controllers/categories_controller.rb`
- Create: `app/views/categories/index.html.erb`, `app/views/categories/show.html.erb`, `app/views/categories/new.html.erb`, `app/views/categories/edit.html.erb`, `app/views/categories/_form.html.erb`
- Test: `spec/requests/categories_spec.rb`

**Interfaces:**
- Consumes: `Budget`, `Category` (reserved guards in model), `Budgeting::MonthEntries` (Task 4), `current_month`, `brl`.
- Produces: `category_path(category, month:)` — the home (Task 9) links category rows here.

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/categories_spec.rb
require "rails_helper"

RSpec.describe "Categories", type: :request do
  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }

  it "creates a category with the month's budget (AC 2)" do
    post categories_path, params: { category: { name: "mercado", budget_amount: "900,00" }, month: "2026-03" }
    category = Category.find_by!(name: "mercado")
    expect(Budget.find_by(category:, month: Date.new(2026, 3, 1)).amount_cents).to eq 90_000
  end

  it "lists categories with the month's budget (AC 2)" do
    category = Category.create!(name: "mercado")
    Budget.create!(category:, month: Date.new(2026, 3, 1), amount_cents: 90_000)
    get categories_path(month: "2026-03")
    expect(response.body).to include("mercado").and include("900,00")
  end

  it "updates name and budget" do
    category = Category.create!(name: "mercado")
    patch category_path(category), params: { category: { name: "feira", budget_amount: "500,00" }, month: "2026-03" }
    expect(category.reload.name).to eq "feira"
    expect(Budget.find_by(category:, month: Date.new(2026, 3, 1)).amount_cents).to eq 50_000
  end

  it "shows the category's expenses in the month, all methods (home drill-down)" do
    card = create_card!
    category = Category.create!(name: "mercado")
    Expense.create!(name: "feira", amount_cents: 2_000, payment_method: "cash", category:, date: Date.new(2026, 3, 5))
    Expense.create!(name: "compra grande", amount_cents: 20_000, payment_method: "credit", card:, category:, date: Date.new(2026, 3, 4))
    get category_path(category, month: "2026-03")
    expect(response.body).to include("feira").and include("compra grande")
  end

  it "deleting a category with expenses moves them to the default (AC 15)" do
    card = create_card!
    category = Category.create!(name: "padaria")
    expense = Expense.create!(name: "pão", amount_cents: 500, payment_method: "cash", category:, date: Date.new(2026, 3, 5))
    purchase = InstallmentPurchase.create!(name: "cesta", total_cents: 10_000, installments_count: 2,
                                           card:, category:, date: Date.new(2026, 3, 5))
    delete category_path(category)
    expect(Category.exists?(category.id)).to be false
    expect(expense.reload.category).to eq others
    expect(purchase.reload.category).to eq others
  end

  it "refuses to delete reserved categories (AC 15)" do
    delete category_path(others)
    expect(Category.exists?(others.id)).to be true
    expect(response).to redirect_to(categories_path)
  end

  it "does not render a delete button for reserved categories (AC 15)" do
    get categories_path
    expect(response.body).not_to include(%(action="#{category_path(others)}"))
  end

  it "renaming the default category is allowed (AC 12)" do
    patch category_path(others), params: { category: { name: "geral" }, month: "2026-03" }
    expect(others.reload.name).to eq "geral"
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/requests/categories_spec.rb`
Expected: FAIL — `CategoriesController` missing.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/categories_controller.rb
class CategoriesController < ApplicationController
  before_action :set_category, only: %i[show edit update destroy]

  def index
    @categories = Category.order(:name)
    @budgets = Budget.where(month: current_month).index_by(&:category_id)
  end

  def show
    @expenses = Budgeting::MonthEntries.expenses(month: current_month, category: @category)
  end

  def new
    @category = Category.new
    @budget_amount = nil
  end

  def create
    @category = Category.new(name: category_params[:name])
    if @category.save
      save_budget
      redirect_to categories_path(month: month_param), notice: "Categoria criada."
    else
      @budget_amount = category_params[:budget_amount]
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @budget_amount = Budget.find_by(category: @category, month: current_month)
                           &.amount_cents&.then { |cents| BrlMoney.format(cents) }
  end

  def update
    if @category.update(name: category_params[:name])
      save_budget
      redirect_to categories_path(month: month_param), notice: "Categoria atualizada."
    else
      @budget_amount = category_params[:budget_amount]
      render :edit, status: :unprocessable_entity
    end
  end

  # Excluir move os gastos (e compras parceladas) para a padrão — o aviso
  # com a contagem fica no turbo_confirm da lista.
  def destroy
    if @category.reserved?
      redirect_to categories_path, alert: "Categoria reservada não pode ser excluída." and return
    end
    default = Category.find_by!(role: "others")
    ActiveRecord::Base.transaction do
      @category.expenses.update_all(category_id: default.id)
      InstallmentPurchase.where(category: @category).update_all(category_id: default.id)
      @category.reload.destroy!
    end
    redirect_to categories_path, notice: "Categoria excluída; gastos movidos para #{default.name}."
  end

  private

  def set_category = @category = Category.find(params[:id])

  def month_param = current_month.strftime("%Y-%m")

  def category_params = params.require(:category).permit(:name, :budget_amount)

  # Orçado da categoria no mês em contexto. A categoria "cartão de crédito"
  # não aceita orçado manual (validação no model) — o form nem mostra o campo.
  def save_budget
    return if @category.credit_card?
    amount = category_params[:budget_amount]
    return if amount.blank?
    cents = BrlMoney.parse(amount)
    return if cents.nil? || cents.negative?
    budget = Budget.find_or_initialize_by(category: @category, month: current_month)
    budget.update(amount_cents: cents)
  end
end
```

```erb
<%# app/views/categories/_form.html.erb — locals: category:, budget_amount:, url: %>
<%= form_with model: category, url: url, class: "space-y-4" do |f| %>
  <%= render "shared/errors", model: category %>
  <%= hidden_field_tag :month, current_month.strftime("%Y-%m") %>
  <div>
    <%= f.label :name, "Nome", class: "block text-sm mb-1" %>
    <%= f.text_field :name, class: "border rounded p-2 w-full" %>
  </div>
  <% unless category.credit_card? %>
    <div>
      <%= f.label :budget_amount, "Orçado do mês (R$)", class: "block text-sm mb-1" %>
      <%= f.text_field :budget_amount, value: budget_amount, inputmode: "decimal", class: "border rounded p-2 w-full" %>
      <p class="text-xs text-gray-500 mt-1">vale para <%= current_month.strftime("%m/%Y") %></p>
    </div>
  <% end %>
  <%= f.submit "Salvar", class: "bg-blue-600 text-white rounded px-4 py-2" %>
<% end %>
```

```erb
<%# app/views/categories/index.html.erb %>
<div class="flex items-center justify-between mb-2">
  <h1 class="text-lg font-semibold">Categorias</h1>
  <%= link_to "nova categoria", new_category_path, class: "text-blue-600 text-sm" %>
</div>
<%= render "shared/month_nav", path_helper: ->(month:) { categories_path(month:) } %>
<ul class="divide-y bg-white rounded border">
  <% @categories.each do |category| %>
    <li class="p-3 flex items-center justify-between">
      <div>
        <p class="font-medium">
          <%= category.name %>
          <% if category.reserved? %><span class="text-xs text-gray-400">(reservada)</span><% end %>
        </p>
        <p class="text-sm text-gray-500">
          orçado: <%= @budgets[category.id] ? brl(@budgets[category.id].amount_cents) : "—" %>
        </p>
      </div>
      <div class="flex gap-3 text-sm">
        <%= link_to "editar", edit_category_path(category, month: current_month.strftime("%Y-%m")), class: "text-blue-600" %>
        <% unless category.reserved? %>
          <% count = category.expenses.count %>
          <%= button_to "excluir", category_path(category), method: :delete, class: "text-red-600",
                data: { turbo_confirm: "Excluir #{category.name}? #{count} gasto(s) serão movidos para a categoria padrão." } %>
        <% end %>
      </div>
    </li>
  <% end %>
</ul>
```

```erb
<%# app/views/categories/show.html.erb %>
<h1 class="text-lg font-semibold mb-2"><%= @category.name %></h1>
<%= render "shared/month_nav", path_helper: ->(month:) { category_path(@category, month:) } %>
<ul class="divide-y bg-white rounded border">
  <% method_labels = { "credit" => "crédito", "debit" => "débito", "cash" => "dinheiro" } %>
  <% @expenses.each do |expense| %>
    <li class="p-3 flex items-center justify-between">
      <div>
        <p class="font-medium"><%= expense.name %></p>
        <p class="text-sm text-gray-500">
          <%= brl(expense.amount_cents) %> · <%= method_labels[expense.payment_method] %><% if expense.card %> · <%= expense.card.name %><% end %>
        </p>
      </div>
      <%= link_to "editar", edit_expense_path(expense), class: "text-blue-600 text-sm" %>
    </li>
  <% end %>
  <% if @expenses.empty? %><li class="p-3 text-sm text-gray-500">Nenhum gasto nesta categoria no mês.</li><% end %>
</ul>
```

```erb
<%# app/views/categories/new.html.erb %>
<h1 class="text-lg font-semibold mb-4">Nova categoria</h1>
<%= render "form", category: @category, budget_amount: @budget_amount, url: categories_path %>
```

```erb
<%# app/views/categories/edit.html.erb %>
<h1 class="text-lg font-semibold mb-4">Editar categoria</h1>
<%= render "form", category: @category, budget_amount: @budget_amount, url: category_path(@category) %>
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/requests/categories_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/categories_controller.rb app/views/categories spec/requests/categories_spec.rb
git commit -m "feat: categories CRUD with monthly budget and reallocation on delete"
```

---

### Task 9: Home estrutural do mês

**Files:**
- Modify: `app/controllers/home_controller.rb`
- Modify: `app/views/home/show.html.erb`
- Test: `spec/requests/home_spec.rb`

**Interfaces:**
- Consumes: `current_month`, `Budget`, `category_path(category, month:)` (Task 8), `shared/month_nav` (Task 6).
- Produces: the screen W3 will fill with real numbers — keep the row structure (saldo row + category rows) stable.

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/home_spec.rb
require "rails_helper"

RSpec.describe "Home", type: :request do
  before { create_setting!; create_reserved_categories! }

  it "shows the saldo placeholder row and one row per category with its budget" do
    category = Category.create!(name: "mercado")
    Budget.create!(category:, month: Date.new(2026, 3, 1), amount_cents: 90_000)
    get root_path(month: "2026-03")
    expect(response.body).to include("saldo")
    expect(response.body).to include("mercado").and include("900,00")
    expect(response.body).to include("outros").and include("cartão de crédito")
    expect(response.body).to include(category_path(category, month: "2026-03"))
  end

  it "clamps navigation to the first month" do
    get root_path(month: "2025-01")
    expect(response.body).to include("03/2026")
  end

  it "shows the FAB with both actions" do
    get root_path
    expect(response.body).to include(new_expense_path).and include(new_income_path)
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/requests/home_spec.rb`
Expected: FAIL — placeholder view has none of it.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/home_controller.rb
class HomeController < ApplicationController
  def show
    @categories = Category.order(:name)
    @budgets = Budget.where(month: current_month).index_by(&:category_id)
  end
end
```

```erb
<%# app/views/home/show.html.erb %>
<%= render "shared/month_nav", path_helper: ->(month:) { root_path(month:) } %>
<div class="bg-white rounded border divide-y">
  <div class="p-3 flex items-center justify-between bg-gray-50">
    <span class="font-medium">saldo</span>
    <span class="text-gray-400">— <span class="text-xs">(em breve)</span></span>
  </div>
  <% @categories.each do |category| %>
    <%= link_to category_path(category, month: current_month.strftime("%Y-%m")),
          class: "p-3 flex items-center justify-between hover:bg-gray-50" do %>
      <span><%= category.name %></span>
      <span class="text-sm text-gray-500">
        orçado: <%= @budgets[category.id] ? brl(@budgets[category.id].amount_cents) : "—" %>
      </span>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/requests/home_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/home_controller.rb app/views/home/show.html.erb spec/requests/home_spec.rb
git commit -m "feat: structural month home with category rows and budgets"
```

---

### Task 10: Fluxo em lote de exclusão de cartão

**Files:**
- Create: `app/controllers/card_migrations_controller.rb`
- Create: `app/views/card_migrations/new.html.erb`
- Test: `spec/requests/card_migrations_spec.rb`

**Interfaces:**
- Consumes: route `new_card_migration_path(card)` (Task 1; cards#destroy redirects here since Task 3).
- Produces: nothing consumed later.

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/card_migrations_spec.rb
require "rails_helper"

RSpec.describe "CardMigrations", type: :request do
  before { create_setting!; create_reserved_categories! }

  let(:others) { Category.find_by!(role: "others") }
  let!(:card) { create_card!(name: "Azul") }
  let!(:target) { create_card!(name: "Verde") }

  before do
    Expense.create!(name: "mercado", amount_cents: 10_000, payment_method: "credit",
                    card:, category: others, date: Date.new(2026, 3, 4))
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))
  end

  it "shows the counts and the destinations (AC 17)" do
    get new_card_migration_path(card)
    expect(response.body).to include("1 gasto").and include("1 compra parcelada")
    expect(response.body).to include("Verde")
  end

  it "migrates everything to another card and deletes the original (AC 17)" do
    post card_migration_path(card), params: { action_kind: "migrate", target_card_id: target.id }
    expect(Card.exists?(card.id)).to be false
    expect(Expense.find_by!(name: "mercado").card).to eq target
    purchase = InstallmentPurchase.find_by!(name: "sofá")
    expect(purchase.card).to eq target
    expect(purchase.expenses.pluck(:card_id).uniq).to eq [target.id]
  end

  it "deletes everything and the card (AC 17)" do
    post card_migration_path(card), params: { action_kind: "delete" }
    expect(Card.exists?(card.id)).to be false
    expect(Expense.where(name: "mercado")).to be_empty
    expect(InstallmentPurchase.where(name: "sofá")).to be_empty
  end

  it "requires a target card when migrating" do
    post card_migration_path(card), params: { action_kind: "migrate", target_card_id: "" }
    expect(response).to redirect_to(new_card_migration_path(card))
    expect(Card.exists?(card.id)).to be true
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/requests/card_migrations_spec.rb`
Expected: FAIL — controller missing.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/card_migrations_controller.rb
# Fluxo em lote antes de excluir um cartão com gastos: migrar tudo para
# outro cartão ou excluir tudo; ao concluir, o cartão é excluído junto.
class CardMigrationsController < ApplicationController
  before_action :set_card

  def new
    @expense_count = @card.expenses.where(installment_purchase_id: nil).count
    @purchase_count = @card.installment_purchases.count
    @other_cards = Card.where.not(id: @card.id).order(:name)
  end

  def create
    case params[:action_kind]
    when "migrate" then migrate_and_destroy
    when "delete" then delete_and_destroy
    else redirect_to new_card_migration_path(@card), alert: "Escolha o que fazer com os gastos."
    end
  end

  private

  def set_card = @card = Card.find(params[:card_id])

  def migrate_and_destroy
    target = Card.find_by(id: params[:target_card_id])
    if target.nil? || target == @card
      redirect_to new_card_migration_path(@card), alert: "Escolha o cartão de destino." and return
    end
    ActiveRecord::Base.transaction do
      # update_all: reatribuição em massa sem callbacks — as validações dos
      # gastos não mudam (mesmo método, categoria e datas), só o cartão.
      @card.expenses.update_all(card_id: target.id)
      @card.installment_purchases.update_all(card_id: target.id)
      @card.reload.destroy!
    end
    redirect_to cards_path, notice: "Gastos migrados para #{target.name}; cartão #{@card.name} excluído."
  end

  def delete_and_destroy
    name = @card.name
    ActiveRecord::Base.transaction do
      @card.installment_purchases.destroy_all
      @card.expenses.destroy_all
      @card.reload.destroy!
    end
    redirect_to cards_path, notice: "Gastos excluídos junto com o cartão #{name}."
  end
end
```

```erb
<%# app/views/card_migrations/new.html.erb %>
<h1 class="text-lg font-semibold mb-4">Excluir <%= @card.name %></h1>
<p class="text-sm bg-amber-50 border border-amber-200 rounded p-3 mb-4">
  Este cartão tem <strong><%= @expense_count %> gasto(s) avulso(s)</strong> e
  <strong><%= @purchase_count %> compra(s) parcelada(s)</strong>.
  Escolha o destino deles para concluir a exclusão.
</p>

<% if @other_cards.any? %>
  <%= form_with url: card_migration_path(@card), method: :post, class: "space-y-3 mb-6" do %>
    <%= hidden_field_tag :action_kind, "migrate" %>
    <label class="block text-sm">Migrar tudo para:</label>
    <%= select_tag :target_card_id, options_from_collection_for_select(@other_cards, :id, :name),
          include_blank: "escolha…", class: "border rounded p-2 w-full" %>
    <%= submit_tag "Migrar e excluir cartão", class: "bg-blue-600 text-white rounded px-4 py-2",
          data: { turbo_confirm: "Migrar todos os gastos e excluir o cartão #{@card.name}?" } %>
  <% end %>
<% end %>

<%= form_with url: card_migration_path(@card), method: :post do %>
  <%= hidden_field_tag :action_kind, "delete" %>
  <%= submit_tag "Excluir todos os gastos e o cartão", class: "bg-red-600 text-white rounded px-4 py-2",
        data: { turbo_confirm: "Excluir os #{@expense_count} gasto(s), as #{@purchase_count} compra(s) parcelada(s) e o cartão #{@card.name}? Isso não pode ser desfeito." } %>
<% end %>
```

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/requests/card_migrations_spec.rb spec/requests/cards_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/card_migrations_controller.rb app/views/card_migrations spec/requests/card_migrations_spec.rb
git commit -m "feat: batch card deletion flow with migrate/delete options"
```

---

### Task 11: Configurações

**Files:**
- Create: `app/controllers/settings_controller.rb`
- Create: `app/views/settings/edit.html.erb`
- Test: `spec/requests/settings_spec.rb`

**Interfaces:**
- Consumes: `Setting` (model guards moving `first_month` past existing entries), `BrlMoney`, `categories#update` (Task 8 — rename forms post there).
- Produces: `edit_settings_path` page (linked from nav and the derived income row).

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/settings_spec.rb
require "rails_helper"

RSpec.describe "Settings", type: :request do
  before { create_setting!(initial_balance_cents: 10_000); create_reserved_categories! }

  it "shows current values and the reserved category rename forms (AC 12/18)" do
    get edit_settings_path
    expect(response.body).to include("2026-03").and include("100,00")
    expect(response.body).to include("outros").and include("cartão de crédito")
  end

  it "updates first month and initial balance (AC 18)" do
    patch settings_path, params: { setting: { first_month: "2026-02", initial_balance: "-250,00" } }
    expect(Setting.instance.first_month).to eq Date.new(2026, 2, 1)
    expect(Setting.instance.initial_balance_cents).to eq(-25_000)
  end

  it "refuses moving first month after existing entries (motor rule)" do
    Income.create!(name: "salário", amount_cents: 100, date: Date.new(2026, 3, 1))
    patch settings_path, params: { setting: { first_month: "2026-04", initial_balance: "100,00" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Setting.instance.first_month).to eq Date.new(2026, 3, 1)
  end
end
```

- [ ] **Step 2: Run, verify failure**

Run: `bin/rspec spec/requests/settings_spec.rb`
Expected: FAIL — controller missing.

- [ ] **Step 3: Implement**

```ruby
# app/controllers/settings_controller.rb
class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
    @reserved = Category.where.not(role: nil).order(:role)
  end

  def update
    @setting = Setting.instance
    @setting.assign_attributes(first_month: parse_month(params[:setting][:first_month]),
                               initial_balance_cents: BrlMoney.parse(params[:setting][:initial_balance]) || 0)
    if @setting.save
      redirect_to edit_settings_path, notice: "Configurações salvas."
    else
      @reserved = Category.where.not(role: nil).order(:role)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def parse_month(text)
    Date.strptime(text.to_s, "%Y-%m")
  rescue ArgumentError
    nil
  end
end
```

```erb
<%# app/views/settings/edit.html.erb %>
<h1 class="text-lg font-semibold mb-4">Configurações</h1>

<%= form_with url: settings_path, scope: :setting, method: :patch, class: "space-y-4 mb-8" do |f| %>
  <%= render "shared/errors", model: @setting %>
  <div>
    <%= f.label :first_month, "Primeiro mês", class: "block text-sm mb-1" %>
    <%= f.month_field :first_month, value: @setting.first_month.strftime("%Y-%m"), class: "border rounded p-2 w-full" %>
    <p class="text-xs text-gray-500 mt-1">A linha do tempo começa aqui; não pode passar de um mês que já tem lançamentos.</p>
  </div>
  <div>
    <%= f.label :initial_balance, "Saldo inicial (R$)", class: "block text-sm mb-1" %>
    <%= f.text_field :initial_balance, value: BrlMoney.format(@setting.initial_balance_cents),
          inputmode: "decimal", class: "border rounded p-2 w-full" %>
  </div>
  <%= f.submit "Salvar", class: "bg-blue-600 text-white rounded px-4 py-2" %>
<% end %>

<h2 class="font-medium mb-2">Categorias reservadas</h2>
<p class="text-sm text-gray-500 mb-3">Renomeáveis; não podem ser excluídas.</p>
<div class="space-y-3">
  <% @reserved.each do |category| %>
    <%= form_with model: category, url: category_path(category), class: "flex gap-2" do |f| %>
      <%= f.text_field :name, class: "border rounded p-2 flex-1" %>
      <%= f.submit "Renomear", class: "bg-gray-700 text-white rounded px-3 py-2 text-sm" %>
    <% end %>
  <% end %>
</div>
```

Note: the rename forms post to `categories#update` with only `category[name]` — Task 8's controller permits `budget_amount` as optional, and `save_budget` no-ops when it's blank, so this works. On rename failure the categories controller renders its own edit view; acceptable.

- [ ] **Step 4: Run, verify pass**

Run: `bin/rspec spec/requests/settings_spec.rb`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/settings_controller.rb app/views/settings spec/requests/settings_spec.rb
git commit -m "feat: settings screen for first month, initial balance and reserved renames"
```

---

### Task 12: System specs (JS) — FAB, form condicional, confirmações

**Files:**
- Create: `spec/support/system.rb`
- Test: `spec/system/expense_entry_flow_spec.rb`
- Modify: `app/javascript/controllers/index.js` (only if the stimulus controllers weren't auto-registered — with `stimulus-rails` + importmap, `eagerLoadControllersFrom("controllers", application)` in `index.js` picks them up automatically; verify, don't rewrite)

**Interfaces:**
- Consumes: everything above.
- Produces: nothing — final verification layer.

- [ ] **Step 1: Configure system specs**

```ruby
# spec/support/system.rb
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [390, 844]
  end
end
```

Build CSS once so pages render (Propshaft serves it in test):

Run: `bin/rails tailwindcss:build`

- [ ] **Step 2: Write the system spec**

```ruby
# spec/system/expense_entry_flow_spec.rb
require "rails_helper"

RSpec.describe "Expense entry flow", type: :system do
  before { create_setting!; create_reserved_categories! }

  it "redirects to setup when unconfigured" do
    Setting.instance.destroy!
    visit root_path
    expect(page).to have_content("Primeiro acesso")
  end

  it "launches a debit expense through the FAB (AC 4 + FAB)" do
    visit root_path
    find("button[aria-label='Lançar']").click
    click_link "gasto"
    fill_in "Nome", with: "padaria"
    fill_in "expense_entry[amount]", with: "50,00"
    choose "débito"
    click_button "Salvar"
    expect(page).to have_content("Gasto lançado")
    expect(page).to have_content("padaria")
  end

  it "shows card and installment fields only for credit, and hides the reserved category (AC 11/13)" do
    create_card!(name: "Azul")
    visit new_expense_path
    expect(page).to have_no_select("expense_entry[card_id]")
    choose "crédito"
    expect(page).to have_select("expense_entry[card_id]")
    expect(page).to have_field("parcelado")
    option = find("select[name='expense_entry[category_id]'] option", text: "cartão de crédito", visible: :all)
    expect(option).to be_disabled
    check "parcelado"
    expect(page).to have_field("Nº de parcelas")
    expect(page).to have_content("Valor total")
  end

  it "confirms whole-purchase deletion from an installment row (AC 9)" do
    card = create_card!
    others = Category.find_by!(role: "others")
    InstallmentPurchase.create!(name: "sofá", total_cents: 100_000, installments_count: 10,
                                card:, category: others, date: Date.new(2026, 3, 10))
    visit expenses_path(month: "2026-03")
    accept_confirm(/compra parcelada inteira/) do
      first("li", text: "sofá 1/10").find_button("excluir").click
    end
    expect(page).to have_content("Compra parcelada excluída")
    expect(InstallmentPurchase.count).to eq 0
  end
end
```

- [ ] **Step 3: Run, verify (fix if needed)**

Run: `bin/rspec spec/system/expense_entry_flow_spec.rb`
Expected: all pass. Common failures and their real causes:
- Stimulus controller not firing → check `app/javascript/controllers/index.js` registers via `eagerLoadControllersFrom`; if it manually registers only `hello_controller`, add the two new controllers with the same manual pattern.
- `accept_confirm` timeout → Turbo `data-turbo-confirm` uses native `confirm` by default; keep it (do not add a custom dialog).

- [ ] **Step 4: Full suite + lint**

Run: `bin/rspec && bin/rubocop`
Expected: whole suite green; rubocop clean (fix offenses it reports — the project uses rubocop-rails-omakase).

- [ ] **Step 5: Commit**

```bash
git add spec/support/system.rb spec/system app/javascript/controllers/index.js
git commit -m "test: system coverage for FAB, conditional expense form and confirmations"
```

---

## AC → cobertura

| AC | Onde |
|---|---|
| 1 | Task 3 specs (list/create) |
| 2 | Task 8 specs (create/list com orçado) |
| 3 | Task 7 (create/list) |
| 4 | Task 6 + Task 12 (fluxo completo) |
| 5 | Task 5 (statement_of) + Task 6 |
| 6, 7, 8 | Task 5 (série, sobra, parcela inicial) + Task 6 request |
| 9 | Task 5 (recálculo) + Task 6 (edit/delete via parcela) + Task 12 (confirm) |
| 10 | Task 6 (mudança de data → fatura) |
| 11 | Task 6 (aceito no débito / rejeitado no crédito) + Task 12 (option escondida) |
| 12 | Task 5 (default others) + Task 8 (rename) + Task 11 (forms nas configurações) |
| 13 | Task 6 (mensagem + link) + Task 12 |
| 14 | Task 5/6/7 (valores inválidos) |
| 15 | Task 8 (realocação, reservadas sem excluir) |
| 16 | Task 3 (nova vigência, antiga preservada) |
| 17 | Task 10 (migrar/excluir em lote) |
| 18 | Task 7 (linha derivada, saldo inicial → configurações) + Task 11 |
| 19 | Task 5/6/7 (bloqueio de data) |
