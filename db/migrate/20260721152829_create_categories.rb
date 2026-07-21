class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.string :name, null: false
      t.string :role
      t.timestamps
    end
    add_index :categories, :role, unique: true, where: "role IS NOT NULL"
  end
end
