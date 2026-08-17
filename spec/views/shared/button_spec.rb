require "rails_helper"

RSpec.describe "shared/_button", type: :view do
  it "renders a link with the positive variant" do
    render "shared/button", label: "ganho", href: "/incomes/new", variant: :positive
    expect(rendered).to have_css('a.btn.btn-positive[href="/incomes/new"]', text: "ganho")
  end

  it "renders a button with the danger variant by default element" do
    render "shared/button", label: "gasto", variant: :danger
    expect(rendered).to have_css('button.btn.btn-danger[type="button"]', text: "gasto")
  end
end
