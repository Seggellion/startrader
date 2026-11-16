# Read-only presenter for /admin/users/:id (discovery F-09, criteria 11-21).
#
# Loads everything the page needs in a fixed number of queries, independent of
# how many shard memberships, ships or journeys the user has. The view must not
# call ShardUser#current_location, User#active_ship, UserShip#active_travel or
# Setting.get, which all query per call.
module Admin
  class UserOverview
    COORDINATE_KEYS = %w[x y z].freeze

    Membership = Struct.new(:shard_user, :shard, :payload, :raw_location, :stores, :location_name, :location,
      :storage, :coordinates, :ships, :comparisons, keyword_init: true) do
      def location_known? = location_name.present?
      def stale_location? = location_known? && location.nil?
    end

    ShipRow = Struct.new(:user_ship, :location, :journey, :state, :duplicate_journeys,
      :membership_mismatch, keyword_init: true) do
      def stale_location? = user_ship.location_name.present? && location.nil?
    end

    # status: :aligned, :diverged, :unknown, :in_transit, :interdicted
    Comparison = Struct.new(:ship_row, :player_location, :ship_location, :status, keyword_init: true)

    attr_reader :user, :tick, :seconds_per_tick, :memberships, :unlinked_ships, :tick_control,
      :shard_uuid_variant_groups

    def initialize(user)
      @user = user
      load!
    end

    def ship_count = all_ship_rows.size
    def in_transit_count = all_ship_rows.count { |row| row.state&.state.in?(%w[scheduled awaiting_completion]) }
    def interdicted_count = all_ship_rows.count { |row| row.state&.state == "interdicted" }
    def divergence_count = memberships.sum { |m| m.comparisons.count { |c| c.status == :diverged } }
    def unknown_player_location_count = memberships.count { |m| !m.location_known? }

    def all_ship_rows
      memberships.flat_map(&:ships) + unlinked_ships
    end

    def last_record_write_at
      [*memberships.map { |m| m.shard_user.updated_at }, *all_ship_rows.map { |r| r.user_ship.updated_at }].compact.max
    end

    def identity
      {
        twitch_id_matches_uid: user.twitch_id.present? && user.twitch_id == user.uid,
        provider: user.provider
      }
    end

    private

    def load!
      @tick = Tick.order(:id).pick(:current_tick) || 0
      @seconds_per_tick = Tick.seconds_per_tick
      @tick_control = TickControl.order(:id).first

      shard_users = ShardUser.where(user_id: user.id).includes(:shard).order(:id).to_a
      membership_ids = shard_users.map(&:id)
      user_ships = UserShip.where(user_id: user.id)
        .includes(:ship, :shard, user_ship_cargos: :commodity)
        .order(:id).to_a
      journeys = ShipTravel.where(user_ship_id: user_ships.map(&:id), completed_at_tick: nil)
        .includes(:from_location, :to_location).order(:id).to_a
      journeys_by_ship = journeys.group_by(&:user_ship_id)

      payloads = shard_users.to_h { |su| [su.id, payload_hash(su)] }
      names = payloads.values.filter_map { |p| location_name_from(p) } +
        user_ships.filter_map { |s| s.location_name.presence }
      catalog = names.empty? ? {} : Location.where(name: names.uniq).index_by(&:name)

      rows = user_ships.to_h do |ship|
        ship_journeys = journeys_by_ship.fetch(ship.id, [])
        journey = ship_journeys.first
        player_name = location_name_from(payloads[ship.shard_user_id])
        state = journey && begin
          journey.association(:user_ship).target = ship
          # "" (not nil) stops TravelState re-reading ShardUser#current_location_name.
          TravelState.new(journey, tick: tick, duplicate: ship_journeys.size > 1,
            player_location_name: player_name || "")
        end
        [ship.id, ShipRow.new(user_ship: ship, location: catalog[ship.location_name], journey: journey,
          state: state, duplicate_journeys: ship_journeys.size > 1,
          membership_mismatch: ship.shard_user_id.present? && !membership_ids.include?(ship.shard_user_id))]
      end

      @memberships = shard_users.map do |shard_user|
        payload = payloads[shard_user.id]
        name = location_name_from(payload)
        ship_rows = user_ships.select { |s| s.shard_user_id == shard_user.id }.map { |s| rows[s.id] }
        Membership.new(shard_user: shard_user, shard: shard_user.shard, payload: payload,
          raw_location: safe_store(shard_user, :last_location),
          stores: %i[inventory currency stats].to_h { |k| [k.to_s, safe_store(shard_user, k)] },
          location_name: name, location: catalog[name], storage: storage_kind(shard_user),
          coordinates: coordinates_from(payload), ships: ship_rows,
          comparisons: ship_rows.map { |row| compare(name, row) })
      end
      @unlinked_ships = user_ships.reject { |s| membership_ids.include?(s.shard_user_id) }.map { |s| rows[s.id] }

      keys = shard_users.filter_map { |su| su.shard&.channel_uuid&.strip&.downcase }.uniq
      @shard_uuid_variant_groups = if keys.empty?
        0
      else
        Shard.where("lower(btrim(channel_uuid)) IN (?)", keys)
          .group("lower(btrim(channel_uuid))").having("count(*) > 1").count.size
      end
    end

    def compare(player_name, row)
      ship_name = row.user_ship.location_name.presence
      status =
        if row.state&.state == "interdicted" then :interdicted
        elsif row.state&.state.in?(%w[scheduled awaiting_completion]) then :in_transit
        elsif player_name.blank? || ship_name.blank? then :unknown
        elsif player_name == ship_name then :aligned
        else :diverged
        end
      Comparison.new(ship_row: row, player_location: player_name, ship_location: ship_name, status: status)
    end

    # The JSON store coder can yield a Hash, a String, an Array or nil from
    # historical rows, and raises for a bare (non-JSON) string such as a plain
    # location name. Only a Hash is a location payload.
    def payload_hash(shard_user)
      value = safe_store(shard_user, :last_location)
      value.is_a?(Hash) ? value.stringify_keys : nil
    end

    # Falls back to decoding the raw column when the model coder cannot: on the
    # production line `store ..., coder: JSON` raises for native jsonb objects.
    def safe_store(shard_user, attribute)
      shard_user.public_send(attribute)
    rescue JSON::ParserError, TypeError
      raw = shard_user.read_attribute_before_type_cast(attribute)
      decoded = raw.is_a?(String) ? (JSON.parse(raw) rescue nil) : raw
      decoded = (JSON.parse(decoded) rescue decoded) if decoded.is_a?(String)
      decoded.is_a?(Hash) || decoded.is_a?(Array) ? decoded : { "undecodable_raw_value" => raw.to_s.truncate(500) }
    end

    def location_name_from(payload)
      return unless payload
      payload["name"].presence || payload["location_name"].presence
    end

    def coordinates_from(payload)
      return {} unless payload
      payload.slice(*COORDINATE_KEYS)
    end

    def storage_kind(shard_user)
      raw = shard_user.read_attribute_before_type_cast(:last_location)
      case raw
      when nil then "SQL NULL"
      when Hash then "native JSON object"
      when String
        decoded = JSON.parse(raw) rescue nil
        decoded.is_a?(String) ? "double-encoded JSON string" : "JSON object"
      else raw.class.name
      end
    end
  end
end
