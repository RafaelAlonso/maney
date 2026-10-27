require "rails_helper"

RSpec.describe Transfer do
  before { create_setting! }

  let(:itau) { Account.create!(name: "Itaú") }

  def transfer(**attrs)
    Transfer.new({ from_account: Account.primary, to_account: itau, amount_cents: 30_000,
                   date: Date.new(2026, 3, 10) }.merge(attrs))
  end

  it "moves money between two of the person's accounts" do
    expect(transfer).to be_valid
    expect(transfer(note: "saque", to_account: Account.wallet)).to be_valid
  end

  it "refuses the same account on both sides" do
    same = transfer(to_account: Account.primary)
    expect(same).not_to be_valid
    expect(same.errors[:to_account]).to include("deve ser diferente da origem")
  end

  it "refuses a date before the first month" do
    early = transfer(date: Date.new(2026, 2, 28))
    expect(early).not_to be_valid
    expect(early.errors[:date]).to include("anterior ao primeiro mês — a linha do tempo começa nele")
    expect(transfer(date: nil)).not_to be_valid
  end

  it "refuses zero or negative amounts" do
    expect(transfer(amount_cents: 0)).not_to be_valid
    expect(transfer(amount_cents: -100)).not_to be_valid
  end

  it "accepts an archived account (editing old history)" do
    itau.archive!
    expect(transfer(to_account: itau)).to be_valid
  end

  it "keeps an account with transfers from being destroyed" do
    transfer.save!
    expect(itau.destroy).to be(false)
  end
end
