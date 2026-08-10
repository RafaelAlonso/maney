class CreateBudgets < ActiveRecord::Migration[8.0]
  def change
    create_table :budgets do |t|
      t.references :category, null: false, foreign_key: true
      t.date :month, null: false
      t.integer :amount_cents, null: false
      t.timestamps
    end
    add_index :budgets, [ :category_id, :month ], unique: true
  end
end
