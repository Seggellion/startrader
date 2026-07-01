class StarTraderShipSync
  Result = Struct.new(:user, :shard, :shard_user, :user_ship, :ship, keyword_init: true)

  def self.call(**kwargs)
    new(**kwargs).call
  end

  def initialize(
    ship_guid:,
    shard_uuid:,
    player_guid:,
    player_name:,
    ship_slug: nil,
    ship_model: nil,
    default_location_name: nil
  )
    @ship_guid = ship_guid
    @ship_slug = ship_slug
    @ship_model = ship_model
    @shard_uuid = shard_uuid
    @player_guid = player_guid
    @player_name = player_name
    @default_location_name = default_location_name
  end

  def call
    validate_required_identity!

    shard = resolve_shard!
    user, shard_user = find_or_create_user_and_shard_user!(shard)
    user_ship = UserShip.find_by(guid: ship_guid)
    ship = user_ship&.ship || resolve_ship_for_new_user_ship!

    user_ship ||= create_user_ship!(
      user: user,
      shard: shard,
      shard_user: shard_user,
      ship: ship
    )

    validate_user_ship_ownership!(user_ship: user_ship, user: user, shard: shard)

    Result.new(
      user: user,
      shard: shard,
      shard_user: shard_user,
      user_ship: user_ship,
      ship: user_ship.ship
    )
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  private

  attr_reader :ship_guid, :ship_slug, :ship_model, :shard_uuid, :player_guid, :player_name, :default_location_name

  def validate_required_identity!
    raise TradeService::ValidationError, "ship_guid is required" if ship_guid.blank?
    raise TradeService::ValidationError, "shard_uuid is required" if shard_uuid.blank?
    raise TradeService::ValidationError, "player_guid is required" if player_guid.blank?
    raise TradeService::ValidationError, "player_name is required" if player_name.blank?
  end

  def resolve_shard!
    shard = Shard.find_by(channel_uuid: shard_uuid)
    raise ActiveRecord::RecordNotFound, "Shard not found" unless shard

    shard
  end

  def find_or_create_user_and_shard_user!(shard)
    normalized_player_guid = player_guid.to_s.strip
    normalized_player_name = player_name.to_s.strip

    user = User.find_by(twitch_id: normalized_player_guid)

    if user
      user.update!(username: normalized_player_name) if user.username.to_s != normalized_player_name
    else
      user = User.create!(
        username: normalized_player_name,
        twitch_id: normalized_player_guid,
        uid: normalized_player_guid,
        user_type: "player",
        provider: "twitch"
      )
    end

    shard_user = user.shard_users.find_or_create_by!(shard_id: shard.id) do |record|
      record.shard_name = shard.name
    end

    [user, shard_user]
  end

  def resolve_ship_for_new_user_ship!
    if ship_slug.present?
      ship = Ship.where("LOWER(slug) = ?", ship_slug.to_s.strip.downcase).first
      raise ActiveRecord::RecordNotFound, "Ship not found for slug #{ship_slug.inspect}." unless ship

      return ship
    end

    if ship_model.present?
      normalized_model = ship_model.to_s.strip.downcase
      ship = Ship.where("LOWER(model) = ?", normalized_model).first
      raise ActiveRecord::RecordNotFound, "Ship model not found" unless ship

      return ship
    end

    raise TradeService::ValidationError, "ship_slug or ship_model is required when ship_guid not found"
  end

  def create_user_ship!(user:, shard:, shard_user:, ship:)
    user_ship = UserShip.find_or_initialize_by(guid: ship_guid)
    return user_ship unless user_ship.new_record?

    user_ship.assign_attributes(
      user: user,
      ship: ship,
      shard: shard,
      shard_user: shard_user,
      ship_slug: ship.slug,
      shard_name: shard.name,
      location_name: default_location_name,
      total_scu: total_scu_for_ship(ship),
      used_scu: 0,
      status: "docked"
    )
    user_ship.save!
    user_ship
  end

  def total_scu_for_ship(ship)
    return ship.total_scu if ship.respond_to?(:total_scu) && ship.total_scu.present?
    return ship.scu if ship.respond_to?(:scu) && ship.scu.present?
    return ship.cargo_capacity if ship.respond_to?(:cargo_capacity) && ship.cargo_capacity.present?

    0
  end

  def validate_user_ship_ownership!(user_ship:, user:, shard:)
    raise TradeService::ValidationError, "Ship does not belong to this player" unless user_ship.user_id == user.id

    ship_shard_user = user_ship.shard_user
    raise ActiveRecord::RecordNotFound, "Shard user not found" unless ship_shard_user
    raise TradeService::ValidationError, "Ship does not belong to this shard" unless ship_shard_user.shard_id == shard.id
  end
end
