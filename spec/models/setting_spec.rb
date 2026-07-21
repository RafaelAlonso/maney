require "rails_helper"

RSpec.describe Setting do
  it "é um singleton com primeiro mês normalizado e saldo inicial possivelmente negativo" do
    setting = Setting.create!(first_month: Date.new(2026, 3, 15), initial_balance_cents: -30_000)
    expect(setting.first_month).to eq(Date.new(2026, 3, 1))
    expect(Setting.instance).to eq(setting)
    expect(Setting.new(first_month: Date.new(2026, 4, 1), initial_balance_cents: 0)).not_to be_valid
  end
end
