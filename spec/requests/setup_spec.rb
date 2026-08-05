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

  # The initial balance anchors the whole BalanceChain: every month inherits from
  # it. An unreadable value silently becoming zero erases the user's real number
  # across the whole application, behind a success message.
  it "rejects an unparseable initial balance without creating the Setting" do
    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "abc" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
    expect(Setting.instance).to be_nil
  end

  it "rejects a blank initial balance without creating the Setting" do
    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("não é um valor válido")
    expect(Setting.instance).to be_nil
  end

  it "accepts a legitimate zero initial balance" do
    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "0,00" } }
    expect(response).to redirect_to(root_path)
    expect(Setting.instance.initial_balance_cents).to eq 0
  end

  it "accepts a legitimate negative initial balance" do
    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "-250,00" } }
    expect(response).to redirect_to(root_path)
    expect(Setting.instance.initial_balance_cents).to eq(-25_000)
  end

  # A Setting without the reserved categories is the worst possible state: the
  # application boots, `require_setup` lets it through, and every entry without a
  # category breaks looking for the "outros" that was never created.
  it "leaves no Setting behind when the reserved categories cannot be created" do
    allow(Category).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordInvalid.new(Category.new))

    post setup_path, params: { setup: { first_month: "2026-03", initial_balance: "1.234,56" } }

    expect(Setting.instance).to be_nil
    expect(Category.count).to eq 0
  end

  it "asks a brand-new person for first-run setup and gives them their own reserved categories (AC 8)" do
    create_setting!
    create_reserved_categories!
    mine = Category.unscoped.where(role: "others").pluck(:id)

    other = create_user!(email_address: "outra@example.com")
    sign_out_request
    post session_path, params: { email_address: other.email_address,
                                 password: AuthenticationHelpers::PASSWORD }

    get root_path
    expect(response).to redirect_to(setup_path)

    post setup_path, params: { setup: { first_month: "2026-05", initial_balance: "0,00" } }
    follow_redirect!

    theirs = Category.unscoped.where(user_id: other.id)
    expect(theirs.where(role: "others").pluck(:name)).to eq([ "outros" ])
    expect(theirs.where(role: "credit_card").pluck(:name)).to eq([ "cartão de crédito" ])
    expect(theirs.where(role: "others").pluck(:id)).not_to eq(mine)
  end
end
