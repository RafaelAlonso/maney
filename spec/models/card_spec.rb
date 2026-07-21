require "rails_helper"

RSpec.describe Card do
  it "exige nome" do
    expect(Card.new(name: "")).not_to be_valid
    expect(Card.new(name: "Azul")).to be_valid
  end
end
