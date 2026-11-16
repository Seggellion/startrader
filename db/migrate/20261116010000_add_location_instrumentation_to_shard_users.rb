# M03: additive, nullable instrumentation for player location changes.
# NULL on historical rows means "not recorded", not "never changed". No backfill.
class AddLocationInstrumentationToShardUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :shard_users, :location_updated_at, :datetime
    add_column :shard_users, :location_source, :string
  end
end
