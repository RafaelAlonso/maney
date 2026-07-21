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
end
