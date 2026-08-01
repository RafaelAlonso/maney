require "rails_helper"

RSpec.describe Budgeting::YearCalendar do
  before { create_setting!(first_month: Date.new(2026, 3, 1)) }

  def calendar(year: 2026, today: Date.new(2026, 7, 15))
    described_class.new(year:, today:)
  end

  it "lists the twelve beginning-of-months of the year" do
    expect(calendar.months.first).to eq Date.new(2026, 1, 1)
    expect(calendar.months.last).to eq Date.new(2026, 12, 1)
    expect(calendar.months.size).to eq 12
  end

  it "excludes months before the first month and months not yet reached" do
    expect(calendar.active_months).to eq((3..7).map { |month| Date.new(2026, month, 1) })
  end

  it "treats a fully past year as entirely active" do
    expect(calendar(year: 2027, today: Date.new(2028, 1, 1)).active_months.size).to eq 12
  end

  it "treats a year entirely before the first month as having no active months" do
    expect(calendar(year: 2025).active_months).to be_empty
  end

  it "answers active? per month" do
    expect(calendar).to be_active(Date.new(2026, 3, 1))
    expect(calendar).not_to be_active(Date.new(2026, 2, 1))
    expect(calendar).not_to be_active(Date.new(2026, 8, 1))
  end

  # Setting is absent only before setup runs; nothing is on the timeline yet.
  it "has no active months when there is no Setting" do
    Setting.delete_all
    expect(calendar.active_months).to be_empty
  end
end
