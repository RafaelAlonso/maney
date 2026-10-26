class CreateAccounts < ActiveRecord::Migration[8.1]
  def up
    create_table :accounts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :role
      t.datetime :archived_at
      t.timestamps
    end
    add_index :accounts, %i[user_id role], unique: true, where: "role IS NOT NULL"

    # Raw SQL: no default scope may decide whose accounts these are. Every person
    # who already has a Setting gets the pair a new Setting creates (see
    # Setting#create_reserved_accounts).
    execute <<~SQL
      INSERT INTO accounts (user_id, name, role, created_at, updated_at)
      SELECT user_id, 'Conta principal', 'primary', NOW(), NOW() FROM settings
      UNION ALL
      SELECT user_id, 'Carteira', 'wallet', NOW(), NOW() FROM settings
    SQL
  end

  def down
    drop_table :accounts
  end
end
