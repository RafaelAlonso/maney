class CreateCardSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :card_schedules do |t|
      t.references :card, null: false, foreign_key: true
      t.integer :closing_day, null: false
      t.integer :due_day, null: false
      t.date :valid_from, null: false
      t.timestamps
    end
    add_index :card_schedules, [ :card_id, :valid_from ], unique: true
  end
end
