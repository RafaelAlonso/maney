class CreateIncomes < ActiveRecord::Migration[8.0]
  def change
    create_table :incomes do |t|
      t.string :name, null: false
      t.integer :amount_cents, null: false
      t.date :date, null: false
      t.timestamps
    end
  end
end
