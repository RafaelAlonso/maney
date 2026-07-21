require "rails_helper"

RSpec.describe Category do
  it "exige nome e restringe role aos papéis reservados" do
    expect(Category.new(name: "mercado")).to be_valid
    expect(Category.new(name: "")).not_to be_valid
    expect(Category.new(name: "x", role: "banana")).not_to be_valid
  end

  it "permite uma única categoria por papel reservado" do
    Category.create!(name: "outros", role: "others")
    expect(Category.new(name: "outros 2", role: "others")).not_to be_valid
  end

  it "as seeds criam as reservadas e são idempotentes" do
    2.times { Rails.application.load_seed }
    expect(Category.where(role: "others").count).to eq(1)
    expect(Category.where(role: "credit_card").count).to eq(1)
    expect(Category.find_by(role: "credit_card")).to be_credit_card
  end

  it "Fix 2: recusa excluir uma categoria reservada" do
    reserved = Category.create!(name: "cartão de crédito", role: "credit_card")
    expect(reserved.destroy).to be(false)
    expect(reserved.errors[:base]).to be_present
    expect(Category.exists?(reserved.id)).to be(true)
  end

  it "Fix 2: continua livre para excluir uma categoria comum, sem role" do
    plain = Category.create!(name: "mercado")
    expect(plain.destroy).to be_truthy
    expect(Category.exists?(plain.id)).to be(false)
  end

  it "Fix 2: recusa remover ou trocar o role de uma categoria reservada já persistida" do
    reserved = Category.create!(name: "cartão de crédito", role: "credit_card")

    reserved.role = nil
    expect(reserved).not_to be_valid
    expect(reserved.errors[:role]).to be_present

    reserved.reload
    reserved.role = "others"
    expect(reserved).not_to be_valid
    expect(reserved.errors[:role]).to be_present
  end

  it "Fix 2: continua livre para atribuir role a uma categoria que ainda não era reservada" do
    plain = Category.create!(name: "outros")
    plain.role = "others"
    expect(plain).to be_valid
  end
end
