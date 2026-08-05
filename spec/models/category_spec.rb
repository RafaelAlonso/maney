require "rails_helper"

RSpec.describe Category do
  it "requires a name and restricts role to the reserved roles" do
    expect(Category.new(name: "mercado")).to be_valid
    expect(Category.new(name: "")).not_to be_valid
    expect(Category.new(name: "x", role: "banana")).not_to be_valid
  end

  it "allows a single category per reserved role" do
    Category.create!(name: "outros", role: "others")
    expect(Category.new(name: "outros 2", role: "others")).not_to be_valid
  end

  it "Fix 2: refuses to delete a reserved category" do
    reserved = Category.create!(name: "cartão de crédito", role: "credit_card")
    expect(reserved.destroy).to be(false)
    expect(reserved.errors[:base]).to be_present
    expect(Category.exists?(reserved.id)).to be(true)
  end

  it "Fix 2: still free to delete an ordinary category, with no role" do
    plain = Category.create!(name: "mercado")
    expect(plain.destroy).to be_truthy
    expect(Category.exists?(plain.id)).to be(false)
  end

  it "Fix 2: refuses to remove or change the role of an already-persisted reserved category" do
    reserved = Category.create!(name: "cartão de crédito", role: "credit_card")

    reserved.role = nil
    expect(reserved).not_to be_valid
    expect(reserved.errors[:role]).to be_present

    reserved.reload
    reserved.role = "others"
    expect(reserved).not_to be_valid
    expect(reserved.errors[:role]).to be_present
  end

  it "Fix 2: still free to assign a role to a category that wasn't reserved yet" do
    plain = Category.create!(name: "outros")
    plain.role = "others"
    expect(plain).to be_valid
  end
end
