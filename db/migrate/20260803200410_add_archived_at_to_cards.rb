class AddArchivedAtToCards < ActiveRecord::Migration[8.1]
  def change
    add_column :cards, :archived_at, :datetime
  end
end
