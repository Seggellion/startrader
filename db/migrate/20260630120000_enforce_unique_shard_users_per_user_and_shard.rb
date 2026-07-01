class EnforceUniqueShardUsersPerUserAndShard < ActiveRecord::Migration[8.0]
  INDEX_NAME = "index_shard_users_on_user_id_and_shard_id_unique"

  class ShardUserRecord < ActiveRecord::Base
    self.table_name = "shard_users"
  end

  class ShardUserSkillRecord < ActiveRecord::Base
    self.table_name = "shard_user_skills"
  end

  class UserShipRecord < ActiveRecord::Base
    self.table_name = "user_ships"
  end

  def up
    ShardUserRecord.reset_column_information
    ShardUserSkillRecord.reset_column_information
    UserShipRecord.reset_column_information

    backfill_shard_ids_from_names
    backfill_shard_names_from_ids
    cleanup_duplicate_shard_users

    add_foreign_key :shard_users, :users, column: :user_id, validate: false unless foreign_key_exists?(:shard_users, :users, column: :user_id)
    add_foreign_key :shard_users, :shards, column: :shard_id, validate: false unless foreign_key_exists?(:shard_users, :shards, column: :shard_id)

    add_index :shard_users, [:user_id, :shard_id], unique: true, name: INDEX_NAME unless index_exists?(:shard_users, [:user_id, :shard_id], name: INDEX_NAME)
  end

  def down
    remove_index :shard_users, name: INDEX_NAME if index_exists?(:shard_users, name: INDEX_NAME)
    remove_foreign_key :shard_users, column: :shard_id if foreign_key_exists?(:shard_users, :shards, column: :shard_id)
    remove_foreign_key :shard_users, column: :user_id if foreign_key_exists?(:shard_users, :users, column: :user_id)
  end

  def cleanup_duplicate_shard_users
    duplicate_keys.each do |user_id, shard_id|
      shard_users = ShardUserRecord
        .where(user_id: user_id, shard_id: shard_id)
        .order(Arel.sql("created_at ASC NULLS LAST"), :id)
        .to_a

      canonical = shard_users.shift

      shard_users.each do |duplicate|
        merge_duplicate_state!(canonical, duplicate)
        reassign_user_ships!(canonical, duplicate)
        merge_shard_user_skills!(canonical, duplicate)
        ShardUserRecord.where(id: duplicate.id).delete_all
      end
    end
  end

  private

  def backfill_shard_ids_from_names
    execute <<~SQL.squish
      UPDATE shard_users
      SET shard_id = shards.id
      FROM shards
      WHERE shard_users.shard_id IS NULL
        AND shard_users.shard_name IS NOT NULL
        AND LOWER(shards.name) = LOWER(shard_users.shard_name)
    SQL
  end

  def backfill_shard_names_from_ids
    execute <<~SQL.squish
      UPDATE shard_users
      SET shard_name = shards.name
      FROM shards
      WHERE shard_users.shard_id = shards.id
        AND (shard_users.shard_name IS NULL OR shard_users.shard_name <> shards.name)
    SQL
  end

  def duplicate_keys
    ShardUserRecord
      .where.not(shard_id: nil)
      .group(:user_id, :shard_id)
      .having("COUNT(*) > 1")
      .pluck(:user_id, :shard_id)
  end

  def merge_duplicate_state!(canonical, duplicate)
    attrs = {
      inventory: sum_numeric_hashes(canonical.inventory, duplicate.inventory),
      currency: sum_numeric_hashes(canonical.currency, duplicate.currency),
      stats: merge_blank_hash_values(canonical.stats, duplicate.stats),
      last_location: newest_non_empty_location(canonical, duplicate),
      wallet_balance: merged_wallet_balance(canonical.wallet_balance, duplicate.wallet_balance),
      updated_at: [canonical.updated_at, duplicate.updated_at].compact.max || Time.current
    }

    canonical.update_columns(attrs)
    canonical.reload
  end

  def reassign_user_ships!(canonical, duplicate)
    UserShipRecord.where(shard_user_id: duplicate.id).update_all(shard_user_id: canonical.id)
  end

  def merge_shard_user_skills!(canonical, duplicate)
    return unless table_exists?(:shard_user_skills)

    ShardUserSkillRecord.where(shard_user_id: duplicate.id).find_each do |skill|
      canonical_skill = ShardUserSkillRecord.find_by(shard_user_id: canonical.id, skill_name: skill.skill_name)

      if canonical_skill
        canonical_skill.update_columns(skill_value: [canonical_skill.skill_value, skill.skill_value].compact.max)
        skill.delete
      else
        skill.update_columns(shard_user_id: canonical.id)
      end
    end
  end

  def sum_numeric_hashes(canonical_value, duplicate_value)
    canonical_hash = normalized_hash(canonical_value)

    normalized_hash(duplicate_value).each do |key, duplicate_item|
      canonical_item = canonical_hash[key]

      canonical_hash[key] =
        if numeric?(canonical_item) && numeric?(duplicate_item)
          canonical_item + duplicate_item
        elsif blank_value?(canonical_item)
          duplicate_item
        else
          canonical_item
        end
    end

    canonical_hash
  end

  def merge_blank_hash_values(canonical_value, duplicate_value)
    canonical_hash = normalized_hash(canonical_value)

    normalized_hash(duplicate_value).each do |key, duplicate_item|
      canonical_hash[key] = duplicate_item if blank_value?(canonical_hash[key]) && !blank_value?(duplicate_item)
    end

    canonical_hash
  end

  def newest_non_empty_location(canonical, duplicate)
    canonical_location = normalized_hash(canonical.last_location)
    duplicate_location = normalized_hash(duplicate.last_location)

    return canonical_location if duplicate_location.empty?
    return duplicate_location if canonical_location.empty?

    duplicate.updated_at.to_i > canonical.updated_at.to_i ? duplicate_location : canonical_location
  end

  def merged_wallet_balance(canonical_balance, duplicate_balance)
    canonical_decimal = decimal_or_zero(canonical_balance)
    duplicate_decimal = decimal_or_zero(duplicate_balance)

    return duplicate_balance if canonical_decimal.zero? && !duplicate_decimal.zero?

    canonical_balance
  end

  def decimal_or_zero(value)
    return 0.to_d if value.blank?

    BigDecimal(value.to_s)
  end

  def normalized_hash(value)
    case value
    when Hash
      value
    when String
      JSON.parse(value)
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def numeric?(value)
    value.is_a?(Numeric)
  end

  def blank_value?(value)
    value.nil? || value == "" || value == {} || value == []
  end
end
