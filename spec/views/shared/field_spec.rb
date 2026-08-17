require "rails_helper"

RSpec.describe "shared/_field", type: :view do
  it "renders a labeled input" do
    render "shared/field", label: "Valor", name: "amount", value: "10", inputmode: "decimal"
    expect(rendered).to have_css("label.field-label", text: "Valor")
    expect(rendered).to have_css('input.field-input[name="amount"][value="10"][inputmode="decimal"]')
  end

  it "renders an error line when given one" do
    render "shared/field", label: "Valor", name: "amount", error: "obrigatório"
    expect(rendered).to have_css("span.field-error", text: "obrigatório")
  end
end
