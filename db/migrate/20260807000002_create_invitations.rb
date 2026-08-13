class CreateInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :invitations do |t|
      t.string :email_address, null: false
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :cancelled_at
      t.string :delivery_state, null: false, default: "sending"
      t.timestamps
    end

    add_index :invitations, :token_digest, unique: true
    add_index :invitations, :email_address
  end
end
