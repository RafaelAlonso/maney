class CreateExpenses < ActiveRecord::Migration[8.0]
  def change
    create_table :expenses do |t|
      t.string :name, null: false
      t.integer :amount_cents, null: false
      t.date :date
      t.string :payment_method, null: false
      t.references :category, null: false, foreign_key: true
      t.references :card, foreign_key: true
      t.bigint :installment_purchase_id, index: true
      t.integer :installment_number
      t.timestamps
    end
  end
end
