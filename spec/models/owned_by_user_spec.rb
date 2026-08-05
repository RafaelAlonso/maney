require "rails_helper"

RSpec.describe OwnedByUser do
  it "stamps the current person on a new record" do
    create_setting!
    category = Category.create!(name: "mercado")

    expect(category.user).to eq(current_user)
  end

  it "hides another person's records" do
    create_setting!
    mine = Category.create!(name: "mercado")

    other = create_user!(email_address: "outra@example.com")
    theirs = nil
    previous = Current.session
    Current.session = Session.create!(user: other)
    theirs = Category.create!(name: "farmácia")
    Current.session = previous

    expect(Category.pluck(:id)).to include(mine.id)
    expect(Category.pluck(:id)).not_to include(theirs.id)
    expect { Category.find(theirs.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "answers nothing at all when nobody is signed in" do
    create_setting!
    Category.create!(name: "mercado")

    Current.session = nil

    expect(Category.count).to eq(0)
    expect(Setting.instance).to be_nil
  end

  it "gives each person their own Setting, despite the single-row rule" do
    create_setting!(first_month: Date.new(2026, 3, 1))

    other = create_user!(email_address: "outra@example.com")
    Current.session = Session.create!(user: other)

    expect { Setting.create!(first_month: Date.new(2026, 5, 1)) }.not_to raise_error
    expect(Setting.instance.first_month).to eq(Date.new(2026, 5, 1))
  end
end
