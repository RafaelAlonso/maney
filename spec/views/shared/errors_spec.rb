require "rails_helper"

RSpec.describe "shared/_errors", type: :view do
  it "renders a tokenized summary for a model with errors" do
    model = User.new
    model.errors.add(:base, "Mensagem de teste")

    render "shared/errors", model: model

    expect(rendered).to have_css("div.text-money-expense", text: "Mensagem de teste")
    expect(rendered).not_to include("bg-red-50")
  end

  it "renders nothing when the model has no errors" do
    render "shared/errors", model: User.new

    expect(rendered.strip).to be_empty
  end
end
