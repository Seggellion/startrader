# Read-only integrity audit for player/ship locations (M01; discovery P-02..P-05, N-01).
#
# Output is aggregate counts only: no user, ship or shard identifiers, names or
# location values (location *key sets* are schema shapes, not data).
# Payloads are decoded in Ruby because production stores last_location as a
# double-encoded JSON string, which SQL JSON operators cannot read (F-07).
#
# Run in production only through `bin/rails status_location:audit`, which wraps
# this in a PostgreSQL READ ONLY transaction.
class StatusLocationAudit
  BATCH = 500

  def report
    {
      generated_at_unix: Time.current.to_i,
      shard_users: shard_user_section,
      shards: shard_section,
      ships: ship_section,
      pairs: pair_section,
      receipts: receipt_section,
      journeys: journey_section
    }
  end

  private

  def catalog_names
    @catalog_names ||= Location.pluck(:name).to_set
  end

  def player_names
    @player_names ||= {}.tap do |names|
      ShardUser.select(:id, :last_location).find_each(batch_size: BATCH) do |su|
        names[su.id] = name_from(payload(su))
      end
    end
  end

  def shard_user_section
    storage = ShardUser.group(Arel.sql("coalesce(jsonb_typeof(last_location), 'sql_null')")).count
    key_sets = Hash.new(0)
    shapes = Hash.new(0)
    coordinates = 0
    ShardUser.select(:id, :last_location).find_each(batch_size: BATCH) do |su|
      value = safe_value(su)
      shapes[value.class.name] += 1
      next unless value.is_a?(Hash)
      key_sets[value.keys.map(&:to_s).sort.join(",")] += 1
      coordinates += 1 if (value.keys.map(&:to_s) & %w[x y z]).any?
    end
    names = player_names.values
    {
      total: player_names.size,
      storage_types: storage,
      decoded_shapes: shapes,
      key_sets: key_sets,
      with_coordinate_keys: coordinates,
      with_location_name: names.count(&:present?),
      location_not_in_catalog: names.count { |n| n.present? && !catalog_names.include?(n) },
      missing_shard: ShardUser.where.not(shard_id: nil).where.missing(:shard).count +
        ShardUser.where(shard_id: nil).count
    }
  end

  def shard_section
    groups = Shard.where.not(channel_uuid: nil).group(Arel.sql("lower(btrim(channel_uuid))"))
      .having("count(*) > 1").count
    {
      total: Shard.count,
      without_channel_uuid: Shard.where(channel_uuid: nil).count,
      case_or_whitespace_variant_groups: groups.size,
      shards_in_variant_groups: groups.values.sum
    }
  end

  def ship_section
    ships = UserShip.left_joins(:shard_user)
    {
      total: UserShip.count,
      location_blank: UserShip.where(location_name: [nil, ""]).count,
      location_not_in_catalog: UserShip.where.not(location_name: [nil, ""]).pluck(:location_name)
        .count { |n| !catalog_names.include?(n) },
      without_shard_user: UserShip.where(shard_user_id: nil).count,
      shard_user_owned_by_other_user: ships.where.not(shard_user_id: nil)
        .where("shard_users.user_id IS DISTINCT FROM user_ships.user_id").count,
      shard_mismatch_with_shard_user: ships.where.not(shard_user_id: nil)
        .where("shard_users.shard_id IS DISTINCT FROM user_ships.shard_id").count
    }
  end

  def pair_section
    unfinished = ShipTravel.where(completed_at_tick: nil).pluck(:user_ship_id, :is_paused)
      .group_by(&:first).transform_values { |rows| rows.map(&:last) }
    tally = Hash.new(0)
    UserShip.where.not(shard_user_id: nil).pluck(:id, :shard_user_id, :location_name).each do |id, su_id, ship_name|
      paused = unfinished[id]
      player = player_names[su_id]
      status =
        if paused&.any? then :interdicted
        elsif paused then :in_transit
        elsif player.blank? || ship_name.blank? then :unknown
        elsif player == ship_name then :aligned
        else :diverged
        end
      tally[status] += 1
    end
    %i[aligned diverged unknown in_transit interdicted].to_h { |k| [k, tally[k]] }
  end

  def receipt_section
    with_receipts = TravelRequestReceipt.distinct.pluck(:user_ship_id)
    busy = ShipTravel.where(completed_at_tick: nil).distinct.pluck(:user_ship_id)
    locked = with_receipts - busy
    {
      by_outcome: TravelRequestReceipt.group(:outcome).count,
      ships_with_receipts: with_receipts.size,
      ships_status_locked_while_idle: locked.size,
      players_status_locked_while_idle: UserShip.where(id: locked).distinct.count(:shard_user_id)
    }
  end

  def journey_section
    open = ShipTravel.where(completed_at_tick: nil)
    {
      unfinished: open.count,
      paused: open.where(is_paused: true).count,
      paused_zero_sentinel: open.where(is_paused: true, arrival_tick: 0).count,
      gate_travel: open.where(ship_travel_type: "gate_travel").count,
      ships_with_multiple_unfinished: open.group(:user_ship_id).having("count(*) > 1").count.size
    }
  end

  def safe_value(shard_user)
    shard_user.last_location
  rescue JSON::ParserError, TypeError
    :undecodable
  end

  def payload(shard_user)
    value = safe_value(shard_user)
    value.is_a?(Hash) ? value.stringify_keys : nil
  end

  def name_from(payload)
    payload && (payload["name"].presence || payload["location_name"].presence)
  end
end
