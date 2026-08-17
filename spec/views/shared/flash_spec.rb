require "rails_helper"

RSpec.describe "shared/_flash", type: :view do
  it "renders a success bar for a notice" do
    render "shared/flash", notice: "Salvo", alert: nil
    expect(rendered).to have_css("p.flash.flash-success", text: "Salvo")
  end

  it "renders an error bar for an alert" do
    render "shared/flash", notice: nil, alert: "Falhou"
    expect(rendered).to have_css("p.flash.flash-error", text: "Falhou")
  end

  it "renders nothing when both are blank" do
    render "shared/flash", notice: nil, alert: nil
    expect(rendered.strip).to be_empty
  end
end
