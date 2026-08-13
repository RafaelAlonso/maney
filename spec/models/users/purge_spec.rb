require "rails_helper"

RSpec.describe Users::Purge do
  let(:irma) { create_user!(email_address: "irma@example.com") }

  def build_a_whole_budget_for(user)
    as(user) do
      create_setting!
      create_reserved_categories!
      card = create_card!
      category = Category.create!(name: "mercado")
      Income.create!(name: "Salário", amount_cents: 500_000, date: Date.new(2026, 3, 5))
      Expense.create!(name: "Feira", amount_cents: 20_000, date: Date.new(2026, 3, 6),
                      payment_method: "debit", category:)
      InstallmentPurchase.create!(name: "Geladeira", total_cents: 300_000, date: Date.new(2026, 3, 7),
                                  installments_count: 3, first_installment: 1, card:, category:)
      Budget.create!(category:, month: Date.new(2026, 3, 1), amount_cents: 50_000)
    end
  end

  it "leaves nothing of that person in any owned table" do
    build_a_whole_budget_for(irma)

    described_class.new(irma).call

    Users::Purge::DELETION_ORDER.each do |table|
      remaining = table.classify.constantize.unscoped.where(user_id: irma.id).count
      expect(remaining).to eq(0), "#{table} still holds rows for the purged person"
    end
    expect(User.find_by(id: irma.id)).to be_nil
  end

  it "leaves everyone else's rows exactly where they are" do
    build_a_whole_budget_for(irma)
    build_a_whole_budget_for(current_user)
    before = Expense.unscoped.where(user_id: current_user.id).pluck(:id).sort

    described_class.new(irma).call

    expect(Expense.unscoped.where(user_id: current_user.id).pluck(:id).sort).to eq(before)
    expect(Setting.unscoped.where(user_id: current_user.id).count).to eq(1)
  end

  it "erases the invitation that carried their address" do
    Invitation.issue(email_address: irma.email_address, invited_by: current_user)

    described_class.new(irma).call

    expect(Invitation.where(email_address: "irma@example.com").count).to eq(0)
  end

  it "erases the invitations they sent, not just the one addressed to them" do
    Invitation.issue(email_address: "convidada@example.com", invited_by: irma)

    described_class.new(irma).call

    expect(Invitation.where(invited_by_id: irma.id).count).to eq(0)
    expect(User.find_by(id: irma.id)).to be_nil
  end

  it "signs them out of everywhere on the way" do
    Session.create!(user: irma)

    described_class.new(irma).call

    expect(Session.where(user_id: irma.id).count).to eq(0)
  end

  # The structural guard, and the reason DELETION_ORDER is not hand-typed
  # alongside Claim::TABLES: a ninth owned table joining the schema must not be
  # able to survive a purge unnoticed.
  it "covers every table the claim task knows about" do
    expect(described_class::DELETION_ORDER.sort).to eq(Users::Claim::TABLES.sort)
  end
end
