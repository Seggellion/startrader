require "test_helper"
require Rails.root.join("db/migrate/20260630120000_enforce_unique_shard_users_per_user_and_shard").to_s

class ShardUserTest < ActiveSupport::TestCase
  setup do
    StarBitizenRun.delete_all
    UserShipCargo.delete_all
    ShipTravel.delete_all
    UserShip.delete_all
    ShardUserSkill.delete_all
    ShardUser.delete_all
    User.delete_all
    Commodity.delete_all
    Ship.delete_all
    Shard.delete_all
    Location.delete_all

    @shard = Shard.create!(name: "TestShard", region: "us", channel_uuid: "shard-guid")
    @user = User.create!(
      username: "TestPilot",
      twitch_id: "test-pilot-twitch",
      uid: "test-pilot-guid",
      user_type: "player"
    )
    @shard_user = ShardUser.create!(
      user: @user,
      shard: @shard,
      wallet_balance: 10_000,
      inventory: { "Agricium" => 2 },
      currency: { "UEC" => 100 }
    )
    @ship = Ship.create!(model: "Drake Cutter", slug: "drake-cutter", scu: 12, speed: 100)
    @from_location = Location.create!(name: "Orison", classification: "city", star_system_name: "Stanton")
    @to_location = Location.create!(name: "Area18", classification: "city", star_system_name: "Stanton")
    @commodity = Commodity.create!(name: "Agricium", is_sellable: true)
  end

  test "duplicate shard user for the same user and shard is invalid" do
    duplicate = ShardUser.new(user: @user, shard: @shard)

    refute duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "database unique index prevents duplicate shard users when validations are bypassed" do
    now = Time.current

    assert_raises(ActiveRecord::RecordNotUnique) do
      ShardUser.insert_all!(
        [
          {
            user_id: @user.id,
            shard_id: @shard.id,
            shard_name: @shard.name,
            created_at: now,
            updated_at: now
          }
        ]
      )
    end
  end

  test "destroying shard user destroys owned ships cargo travel and skills without destroying user or shard" do
    user_ship = create_user_ship(@shard_user, guid: "ship-guid")
    cargo = UserShipCargo.create!(user_ship: user_ship, commodity: @commodity, scu: 4)
    travel = create_ship_travel(user_ship)
    skill = ShardUserSkill.create!(shard_user: @shard_user, skill_name: "Trading", skill_value: 1.5)
    run = StarBitizenRun.create!(
      user: @user,
      user_ship: user_ship,
      user_ship_cargo: cargo,
      commodity: @commodity,
      commodity_name: @commodity.name,
      profit: 0,
      scu: 4
    )

    @shard_user.destroy!

    refute UserShip.exists?(user_ship.id)
    refute UserShipCargo.exists?(cargo.id)
    refute ShipTravel.exists?(travel.id)
    refute ShardUserSkill.exists?(skill.id)
    assert User.exists?(@user.id)
    assert Shard.exists?(@shard.id)
    assert_nil run.reload.user_ship_id
    assert_nil run.user_ship_cargo_id
  end

  test "duplicate cleanup keeps canonical shard user and merges safe state" do
    index_name = EnforceUniqueShardUsersPerUserAndShard::INDEX_NAME
    connection = ActiveRecord::Base.connection
    remove_unique_index(connection, index_name)

    duplicate = insert_duplicate_shard_user!(
      inventory: { "Agricium" => 3, "Laranite" => 1 },
      currency: { "UEC" => 50 },
      stats: { "rank" => "hauler" },
      last_location: { "name" => "Area18" }
    )
    duplicate_ship = create_user_ship(duplicate, guid: "duplicate-ship-guid")
    ShardUserSkill.create!(shard_user: @shard_user, skill_name: "Trading", skill_value: 1.5)
    ShardUserSkill.create!(shard_user: duplicate, skill_name: "Trading", skill_value: 2.5)
    ShardUserSkill.create!(shard_user: duplicate, skill_name: "Mining", skill_value: 3.0)

    EnforceUniqueShardUsersPerUserAndShard.new.cleanup_duplicate_shard_users

    assert_equal @shard_user.id, duplicate_ship.reload.shard_user_id
    refute ShardUser.exists?(duplicate.id)

    @shard_user.reload
    assert_equal({ "Agricium" => 5, "Laranite" => 1 }, @shard_user.inventory)
    assert_equal({ "UEC" => 150 }, @shard_user.currency)
    assert_equal "hauler", @shard_user.stats["rank"]
    assert_equal({ "name" => "Area18" }, @shard_user.last_location)
    assert_equal 2.5.to_d, ShardUserSkill.find_by!(shard_user: @shard_user, skill_name: "Trading").skill_value
    assert_equal 3.0.to_d, ShardUserSkill.find_by!(shard_user: @shard_user, skill_name: "Mining").skill_value
  ensure
    cleanup_extra_duplicate_rows
    add_unique_index(connection, index_name)
  end

  private

  def create_user_ship(shard_user, guid:)
    UserShip.create!(
      user: @user,
      ship: @ship,
      shard: @shard,
      shard_user: shard_user,
      guid: guid,
      ship_slug: @ship.slug,
      location: @from_location,
      total_scu: @ship.scu,
      used_scu: 0
    )
  end

  def create_ship_travel(user_ship)
    ShipTravel.create!(
      user_ship: user_ship,
      from_location: @from_location,
      to_location: @to_location,
      travel_guid: SecureRandom.uuid,
      departure_tick: 90,
      arrival_tick: 100,
      total_duration_ticks: 10,
      interdict_window_percent: 50
    )
  end

  def insert_duplicate_shard_user!(attributes)
    now = 1.minute.from_now
    result = ShardUser.insert_all!(
      [
        {
          user_id: @user.id,
          shard_id: @shard.id,
          shard_name: @shard.name,
          wallet_balance: 0,
          inventory: attributes.fetch(:inventory),
          currency: attributes.fetch(:currency),
          stats: attributes.fetch(:stats),
          last_location: attributes.fetch(:last_location),
          created_at: now,
          updated_at: now
        }
      ],
      returning: %w[id]
    )

    ShardUser.find(result.rows.first.first)
  end

  def remove_unique_index(connection, index_name)
    connection.remove_index(:shard_users, name: index_name) if connection.index_exists?(:shard_users, name: index_name)
  end

  def add_unique_index(connection, index_name)
    return if connection.index_exists?(:shard_users, [:user_id, :shard_id], name: index_name)

    connection.add_index(:shard_users, [:user_id, :shard_id], unique: true, name: index_name)
  end

  def cleanup_extra_duplicate_rows
    ShardUser.where(user_id: @user.id, shard_id: @shard.id).where.not(id: @shard_user.id).delete_all
  end
end
