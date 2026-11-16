# M04 (F-04, decision Q3): one shard per external identity, compared
# case/whitespace-insensitively. Production audit (M00, release v178) found
# 0 case/whitespace-variant groups, so this index can be built without data
# repair. If it ever fails on duplicates, stop and reconcile them by hand; never
# merge shards automatically.
class AddNormalizedChannelUuidIndexToShards < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :shards, "lower(btrim((channel_uuid)::text))",
      unique: true, where: "channel_uuid IS NOT NULL",
      name: "index_shards_on_normalized_channel_uuid", algorithm: :concurrently
  end
end
