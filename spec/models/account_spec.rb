require "rails_helper"

RSpec.describe Account do
  before { create_setting! }

  it "creating a Setting creates Conta principal and Carteira" do
    expect(Account.primary.name).to eq("Conta principal")
    expect(Account.wallet.name).to eq("Carteira")
  end

  it "allows one primary and one wallet per person" do
    expect(Account.new(name: "x", role: "wallet")).not_to be_valid
    expect(Account.new(name: "x", role: "primary")).not_to be_valid

    as(create_user!(email_address: "irma@example.com")) do
      create_setting!
      expect(Account.primary).to be_persisted
      expect(Account.wallet).to be_persisted
      expect(Account.count).to eq(2)
    end
  end

  it "refuses to archive or destroy a reserved account" do
    expect { Account.wallet.archive! }.to raise_error(ActiveRecord::RecordInvalid) { |error|
      expect(error.record.errors[:base]).to include("não pode ser arquivada")
    }
    primary = Account.primary
    expect(primary.destroy).to be(false)
    expect(primary.errors[:base]).to include("não pode ser excluída")
  end

  it "renames a reserved account" do
    Account.primary.update!(name: "Nubank")
    expect(Account.primary.name).to eq("Nubank")
  end

  it "banks excludes the wallet and keeps nil-role accounts" do
    itau = Account.create!(name: "Itaú")
    expect(Account.banks).to contain_exactly(Account.primary, itau)
  end

  it "archives and reactivates an ordinary account" do
    itau = Account.create!(name: "Itaú")
    itau.archive!
    expect(itau).to be_archived
    expect(Account.active).not_to include(itau)
    itau.reactivate!
    expect(itau).not_to be_archived
  end

  it "orders the primary first, then banks by name, the wallet last" do
    zeta = Account.create!(name: "Zeta")
    alfa = Account.create!(name: "Alfa")
    expect(Account.ordered.to_a).to eq([ Account.primary, alfa, zeta, Account.wallet ])
  end
end
