class AddAccountLifecycleToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :admin, :boolean, null: false, default: false
    add_column :users, :consented_at, :datetime
    add_column :users, :consent_policy_version, :string
    add_column :users, :access_revoked_at, :datetime
    add_column :users, :deleted_at, :datetime

    # The already-claimed install. Its sole account is Rafael's, and coming back
    # up with `admin = false` everywhere would leave the group with no door and
    # no way to open one from inside the app. On a fresh database this matches
    # nothing and does nothing.
    execute "UPDATE users SET admin = TRUE WHERE (SELECT COUNT(*) FROM users) = 1"
  end

  def down
    remove_column :users, :admin
    remove_column :users, :consented_at
    remove_column :users, :consent_policy_version
    remove_column :users, :access_revoked_at
    remove_column :users, :deleted_at
  end
end
