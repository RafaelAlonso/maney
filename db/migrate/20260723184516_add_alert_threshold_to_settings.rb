class AddAlertThresholdToSettings < ActiveRecord::Migration[8.0]
  def change
    add_column :settings, :alert_threshold_percent, :integer, default: 80, null: false
  end
end
