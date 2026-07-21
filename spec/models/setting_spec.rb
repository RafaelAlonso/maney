require "rails_helper"

RSpec.describe Setting do
  it "é um singleton com primeiro mês normalizado e saldo inicial possivelmente negativo" do
    setting = Setting.create!(first_month: Date.new(2026, 3, 15), initial_balance_cents: -30_000)
    expect(setting.first_month).to eq(Date.new(2026, 3, 1))
    expect(Setting.instance).to eq(setting)
    expect(Setting.new(first_month: Date.new(2026, 4, 1), initial_balance_cents: 0)).not_to be_valid
  end

  it "Fix 3: recusa mover first_month para depois de um lançamento já existente" do
    setting = Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
    Income.create!(name: "salário", amount_cents: 300_000, date: Date.new(2026, 1, 10))

    setting.first_month = Date.new(2026, 2, 1)
    expect(setting).not_to be_valid
    expect(setting.errors[:first_month]).to be_present

    setting.reload
    expect(setting.first_month).to eq(Date.new(2026, 1, 1))
  end

  it "Fix 3: continua livre para mover first_month para uma data anterior, mesmo com lançamentos" do
    setting = Setting.create!(first_month: Date.new(2026, 2, 1), initial_balance_cents: 0)
    Income.create!(name: "salário", amount_cents: 300_000, date: Date.new(2026, 2, 10))

    setting.first_month = Date.new(2026, 1, 1)
    expect(setting).to be_valid
  end

  it "Fix 3: sem nenhum lançamento, first_month continua livre para mover em qualquer direção" do
    setting = Setting.create!(first_month: Date.new(2026, 1, 1), initial_balance_cents: 0)
    setting.first_month = Date.new(2026, 6, 1)
    expect(setting).to be_valid
  end
end
