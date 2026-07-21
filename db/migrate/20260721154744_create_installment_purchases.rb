class CreateInstallmentPurchases < ActiveRecord::Migration[8.0]
  def change
    create_table :installment_purchases do |t|
      t.string :name, null: false
      t.integer :total_cents, null: false
      t.integer :installments_count, null: false
      t.integer :first_installment, null: false, default: 1
      t.date :date, null: false
      t.references :card, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.timestamps
    end
    add_foreign_key :expenses, :installment_purchases
  end
end
