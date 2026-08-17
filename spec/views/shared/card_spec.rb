require "rails_helper"

RSpec.describe "shared/_card", type: :view do
  it "renders the card chrome with the token class and preserves the heading API" do
    render layout: "shared/card", locals: { title: "Resumo", heading_id: "resumo-title", note: "só neste cartão" } do
      "corpo"
    end
    expect(rendered).to have_css("section.card > h2#resumo-title", text: "Resumo")
    expect(rendered).to have_css("section.card", text: "corpo")
    expect(rendered).to have_css("section.card p", text: "só neste cartão")
  end
end
