require "rails_helper"

RSpec.describe "shared/_empty_state", type: :view do
  it "renders a styled empty state with the message" do
    render "shared/empty_state", message: "Nenhum gasto neste mês."
    expect(rendered).to have_css("div.empty-state", text: "Nenhum gasto neste mês.")
  end
end
