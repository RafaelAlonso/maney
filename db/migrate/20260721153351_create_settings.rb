class CreateSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :settings do |t|
      t.date :first_month, null: false
      t.integer :initial_balance_cents, null: false, default: 0
      t.timestamps
    end
  end
end
