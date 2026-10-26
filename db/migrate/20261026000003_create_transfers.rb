class CreateTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :transfers do |t|
      t.references :user, null: false, foreign_key: true
      t.references :from_account, null: false, foreign_key: { to_table: :accounts }
      t.references :to_account, null: false, foreign_key: { to_table: :accounts }
      t.integer :amount_cents, null: false
      t.date :date, null: false
      t.string :note
      t.timestamps
    end
    add_check_constraint :transfers, "from_account_id <> to_account_id", name: "transfers_between_two_accounts"
    add_check_constraint :transfers, "amount_cents > 0", name: "transfers_amount_positive"
  end
end
