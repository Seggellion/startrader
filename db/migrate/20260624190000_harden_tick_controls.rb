class HardenTickControls < ActiveRecord::Migration[8.0]
  def up
    add_column :tick_controls, :singleton_key, :integer unless column_exists?(:tick_controls, :singleton_key)
    add_column :tick_controls, :last_tick_started_at, :datetime unless column_exists?(:tick_controls, :last_tick_started_at)
    add_column :tick_controls, :last_tick_completed_at, :datetime unless column_exists?(:tick_controls, :last_tick_completed_at)
    add_column :tick_controls, :last_tick_failed_at, :datetime unless column_exists?(:tick_controls, :last_tick_failed_at)
    add_column :tick_controls, :last_tick_error, :text unless column_exists?(:tick_controls, :last_tick_error)
    add_column :tick_controls, :last_tick_error_class, :string unless column_exists?(:tick_controls, :last_tick_error_class)
    add_column :tick_controls, :last_tick_job_id, :string unless column_exists?(:tick_controls, :last_tick_job_id)
    add_column :tick_controls, :last_heartbeat_at, :datetime unless column_exists?(:tick_controls, :last_heartbeat_at)
    add_column :tick_controls, :failure_count, :integer, default: 0 unless column_exists?(:tick_controls, :failure_count)
    add_column :tick_controls, :last_recovered_at, :datetime unless column_exists?(:tick_controls, :last_recovered_at)

    execute <<~SQL.squish
      DELETE FROM tick_controls
      WHERE id NOT IN (SELECT MIN(id) FROM tick_controls)
    SQL

    execute "UPDATE tick_controls SET singleton_key = 1 WHERE singleton_key IS NULL"
    change_column_default :tick_controls, :singleton_key, 1
    change_column_null :tick_controls, :singleton_key, false, 1
    change_column_default :tick_controls, :failure_count, 0
    change_column_null :tick_controls, :failure_count, false, 0

    add_index :tick_controls, :singleton_key, unique: true unless index_exists?(:tick_controls, :singleton_key)
  end

  def down
    remove_index :tick_controls, :singleton_key if index_exists?(:tick_controls, :singleton_key)
    remove_column :tick_controls, :last_recovered_at if column_exists?(:tick_controls, :last_recovered_at)
    remove_column :tick_controls, :failure_count if column_exists?(:tick_controls, :failure_count)
    remove_column :tick_controls, :last_heartbeat_at if column_exists?(:tick_controls, :last_heartbeat_at)
    remove_column :tick_controls, :last_tick_job_id if column_exists?(:tick_controls, :last_tick_job_id)
    remove_column :tick_controls, :last_tick_error_class if column_exists?(:tick_controls, :last_tick_error_class)
    remove_column :tick_controls, :last_tick_error if column_exists?(:tick_controls, :last_tick_error)
    remove_column :tick_controls, :last_tick_failed_at if column_exists?(:tick_controls, :last_tick_failed_at)
    remove_column :tick_controls, :last_tick_completed_at if column_exists?(:tick_controls, :last_tick_completed_at)
    remove_column :tick_controls, :last_tick_started_at if column_exists?(:tick_controls, :last_tick_started_at)
    remove_column :tick_controls, :singleton_key if column_exists?(:tick_controls, :singleton_key)
  end
end
