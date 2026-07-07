
  # app/services/trade_service.rb

class TradeService
    BASE_LOADING_TICKS = 10
    LOADING_TICKS_PER_SCU = 2

    class InsufficientCreditsError < StandardError; end
    class InsufficientCapacityError < StandardError; end
    class CommodityNotAvailableError < StandardError; end
    class LocationMismatchError < StandardError; end
    class InsufficientInventoryError < StandardError; end
    class UserNotFoundError < StandardError; end
    class ShipNotFoundError < StandardError; end
    class ValidationError < StandardError; end
  
    def self.status(
      ship_guid: nil,
      ship_model: nil,
      shard_uuid: nil,
      player_guid: nil,
      player_name: nil,
      location: nil,
      wallet_balance: nil,
      username: nil,
      shard: nil,
      request_id: nil
    )
      has_new_payload = ship_guid.present? || ship_model.present? || shard_uuid.present? ||
        player_guid.present? || player_name.present?

      Rails.logger.info(
        "[TradeService.status] path=#{has_new_payload ? 'ship_guid' : 'legacy'} " \
        "ship_guid_present=#{ship_guid.present?} ship_model_present=#{ship_model.present?} " \
        "shard_uuid_present=#{shard_uuid.present?} " \
        "player_guid_present=#{player_guid.present?} player_name_present=#{player_name.present?} " \
        "location_present=#{location.present?} " \
        "username_present=#{username.present?} shard_present=#{shard.present?} " \
        "request_id=#{request_id.inspect}"
      )

      if has_new_payload
        raise ValidationError, 'ship_guid is required' if ship_guid.blank?
        raise ValidationError, 'ship_model is required' if ship_model.blank?
        raise ValidationError, 'shard_uuid is required' if shard_uuid.blank?
        raise ValidationError, 'player_guid is required' if player_guid.blank?
        raise ValidationError, 'player_name is required' if player_name.blank?

        return status_by_ship_guid(
          ship_guid: ship_guid,
          ship_model: ship_model,
          shard_uuid: shard_uuid,
          player_guid: player_guid,
          player_name: player_name,
          location: location,
          wallet_balance: wallet_balance,
          request_id: request_id
        )
      end

      raise ValidationError, 'username is required for legacy status' if username.blank?
      raise ValidationError, 'shard is required for legacy status' if shard.blank?

      legacy_status(username: username, location: location, wallet_balance: wallet_balance, shard: shard, request_id: request_id)
    end

    def self.status_by_ship_guid(ship_guid:, ship_model:, shard_uuid:, player_guid:, player_name:, location: nil, wallet_balance: nil, request_id: nil)
      validate_wallet_balance!(wallet_balance)
      resolved_location = resolve_status_location!(
        location_name: location,
        player_name: player_name,
        shard_uuid: shard_uuid,
        ship_guid: ship_guid
      )

      sync = authoritative_status_sync!(
        ship_guid: ship_guid,
        ship_model: ship_model,
        shard_uuid: shard_uuid,
        player_guid: player_guid,
        player_name: player_name,
        wallet_balance: wallet_balance,
        location_name: location,
        resolved_location: resolved_location,
        request_id: request_id
      )

      status_response_for(shard_user: sync.shard_user, user_ship: sync.user_ship, wallet_balance: wallet_balance, request_id: request_id)
    end

    def self.authoritative_status_sync!(ship_guid:, ship_model:, shard_uuid:, player_guid:, player_name:, wallet_balance:, location_name:, resolved_location:, request_id: nil)
      shard = find_or_create_status_shard!(shard_uuid)
      user = find_or_create_status_user!(player_guid: player_guid, player_name: player_name)
      shard_user = user.shard_users.find_or_create_by!(shard_id: shard.id) do |record|
        record.shard_name = shard.name
      end
      ship = find_or_create_status_ship!(ship_model)
      user_ship = UserShip.find_or_initialize_by(guid: ship_guid)

      was_new = user_ship.new_record?
      previous_shard_user_location = shard_user.current_location_name
      previous_user_ship_location = user_ship.location_name
      previous_user_ship_user_id = user_ship.user_id
      previous_user_ship_shard_id = user_ship.shard_id
      previous_user_ship_shard_user_id = user_ship.shard_user_id

      ActiveRecord::Base.transaction do
        shard_user.shard_name = shard.name
        shard_user.wallet_balance = wallet_balance if wallet_balance.present?
        shard_user.save! if shard_user.changed?
        shard_user.update_current_location!(resolved_location) if resolved_location

        assign_authoritative_status_user_ship!(
          user_ship: user_ship,
          user: user,
          shard: shard,
          shard_user: shard_user,
          ship: ship,
          location: resolved_location
        )
      end

      log_authoritative_status_sync(
        player_name: player_name,
        player_guid: player_guid,
        shard_uuid: shard_uuid,
        ship_guid: ship_guid,
        incoming_location: location_name,
        resolved_location: resolved_location,
        previous_shard_user_location: previous_shard_user_location,
        previous_user_ship_location: previous_user_ship_location,
        user_ship_was_new: was_new,
        user_ship: user_ship,
        request_id: request_id,
        user_ship_overwrote_associations: previous_user_ship_user_id != user.id ||
          previous_user_ship_shard_id != shard.id ||
          previous_user_ship_shard_user_id != shard_user.id
      )

      StarTraderShipSync::Result.new(
        user: user,
        shard: shard,
        shard_user: shard_user,
        user_ship: user_ship,
        ship: ship
      )
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def self.find_or_create_status_shard!(shard_uuid)
      normalized_shard_uuid = shard_uuid.to_s.strip
      shard = Shard.find_by(channel_uuid: normalized_shard_uuid)
      return shard if shard

      Shard.create!(
        name: "Shard #{normalized_shard_uuid}",
        region: "unknown",
        channel_uuid: normalized_shard_uuid
      )
    end

    def self.find_or_create_status_user!(player_guid:, player_name:)
      normalized_player_guid = player_guid.to_s.strip
      normalized_player_name = player_name.to_s.strip

      user = User.find_by(twitch_id: normalized_player_guid) || User.find_by(uid: normalized_player_guid)
      if user
        attrs = { username: normalized_player_name, twitch_id: normalized_player_guid }
        if user.uid.blank? ||
            user.uid == normalized_player_guid ||
            !User.where(uid: normalized_player_guid).where.not(id: user.id).exists?
          attrs[:uid] = normalized_player_guid
        end
        user.update!(attrs)
        return user
      end

      User.create!(
        username: normalized_player_name,
        twitch_id: normalized_player_guid,
        uid: normalized_player_guid,
        user_type: "player",
        provider: "twitch"
      )
    end

    def self.find_or_create_status_ship!(ship_model)
      normalized_model = ship_model.to_s.strip
      ship = Ship.where("LOWER(model) = ?", normalized_model.downcase).first
      return ship if ship

      Ship.create!(model: normalized_model)
    end

    def self.assign_authoritative_status_user_ship!(user_ship:, user:, shard:, shard_user:, ship:, location:)
      user_ship.assign_attributes(
        user: user,
        shard: shard,
        shard_user: shard_user,
        shard_name: shard.name,
        ship: ship,
        ship_slug: ship.slug,
        total_scu: user_ship.total_scu.presence || total_scu_for_ship(ship),
        used_scu: user_ship.used_scu.presence || 0,
        status: user_ship.status.presence || "docked"
      )
      user_ship.location_name = location.name if location
      user_ship.save!
    end

    def self.log_authoritative_status_sync(player_name:, player_guid:, shard_uuid:, ship_guid:, incoming_location:, resolved_location:, previous_shard_user_location:, previous_user_ship_location:, user_ship_was_new:, user_ship:, request_id:, user_ship_overwrote_associations:)
      Rails.logger.info(
        "[TradeService.status] authoritative_sync " \
        "request_id=#{request_id.inspect} " \
        "player=#{player_name.inspect} player_guid=#{player_guid.inspect} " \
        "shard_uuid=#{shard_uuid.inspect} ship_guid=#{ship_guid.inspect} " \
        "previous_shard_user_location=#{previous_shard_user_location.inspect} " \
        "previous_user_ship_location=#{previous_user_ship_location.inspect} " \
        "incoming_location=#{incoming_location.inspect} " \
        "resolved_location_id=#{resolved_location&.id.inspect} " \
        "resolved_location_name=#{resolved_location&.name.inspect} " \
        "user_ship_id=#{user_ship.id.inspect} user_ship_action=#{user_ship_was_new ? 'created' : 'updated'} " \
        "user_ship_associations_overwritten=#{user_ship_overwrote_associations}"
      )
    end

    def self.resolve_status_location!(location_name:, player_name:, shard_uuid:, ship_guid:)
      return if location_name.blank?

      resolved_location = LocationResolver.resolve_exact(location_name)
      return resolved_location if resolved_location

      Rails.logger.warn(
        "[TradeService.status] location_update failed " \
        "player=#{player_name.inspect} shard_uuid=#{shard_uuid.inspect} " \
        "ship_guid=#{ship_guid.inspect} incoming_location=#{location_name.inspect}"
      )
      raise ValidationError, "Location not found: #{location_name}"
    end

    def self.update_status_location!(shard_user:, user_ship:, location_name:, resolved_location:, player_name:, shard_uuid:, ship_guid:)
      return unless resolved_location

      Rails.logger.info(
        "[TradeService.status] location_update applying " \
        "player=#{player_name.inspect} shard_uuid=#{shard_uuid.inspect} " \
        "ship_guid=#{ship_guid.inspect} incoming_location=#{location_name.inspect} " \
        "resolved_location_id=#{resolved_location.id} resolved_location_name=#{resolved_location.name.inspect}"
      )

      ActiveRecord::Base.transaction do
        shard_user.update_current_location!(resolved_location)
        user_ship&.update!(location_name: resolved_location.name)
      end

      Rails.logger.info(
        "[TradeService.status] location_update applied " \
        "player=#{player_name.inspect} shard_uuid=#{shard_uuid.inspect} " \
        "ship_guid=#{ship_guid.inspect} incoming_location=#{location_name.inspect} " \
        "resolved_location_id=#{resolved_location.id} resolved_location_name=#{resolved_location.name.inspect}"
      )
    end

    def self.legacy_status(username:, location: nil, wallet_balance: nil, shard:, request_id: nil)
      raise ValidationError, 'username is required for legacy status' if username.blank?
      raise ValidationError, 'shard is required for legacy status' if shard.blank?

      validate_wallet_balance!(wallet_balance)
      resolved_location = resolve_status_location!(
        location_name: location,
        player_name: username,
        shard_uuid: shard,
        ship_guid: nil
      )

      shard_record = Shard.find_by(channel_uuid: shard)
      raise ActiveRecord::RecordNotFound, 'Shard not found' unless shard_record

      user = find_or_create_user(username, shard_record)
      shard_user = user.shard_users.find_by(shard_id: shard_record.id)
      raise ActiveRecord::RecordNotFound, 'Shard user not found' unless shard_user
      user_ship = shard_user.user_ships.order(updated_at: :desc).first

      update_status_location!(
        shard_user: shard_user,
        user_ship: user_ship,
        location_name: location,
        resolved_location: resolved_location,
        player_name: username,
        shard_uuid: shard,
        ship_guid: user_ship&.guid
      )

      status_response_for(
        shard_user: shard_user,
        user_ship: user_ship,
        wallet_balance: wallet_balance,
        request_id: request_id
      )

      # ✅ Check if user already has a ship
      
    
      # Gather Cargo Information
    end

    def self.find_ship_by_model!(ship_model)
      raise ValidationError, 'ship_model is required' if ship_model.blank?

      normalized_model = ship_model.to_s.strip.downcase
      ship = Ship.where('LOWER(model) = ?', normalized_model).first
      raise ActiveRecord::RecordNotFound, 'Ship model not found' unless ship

      ship
    end

    def self.find_or_create_user_by_player_guid!(player_guid:, player_name:, shard:)
      raise ValidationError, 'player_guid is required' if player_guid.blank?
      raise ValidationError, 'player_name is required' if player_name.blank?
      raise ActiveRecord::RecordNotFound, 'Shard not found' unless shard

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
          user_type: 'player',
          provider: 'twitch'
        )
      end

      shard_user = user.shard_users.find_or_create_by!(shard_id: shard.id) do |record|
        record.shard_name = shard.name
      end

      [user, shard_user]
    end

    def self.validate_status_ship_ownership!(user_ship:, user:, shard:)
      raise ValidationError, 'Ship does not belong to this player' unless user_ship.user_id == user.id

      ship_shard_user = user_ship.shard_user
      raise ActiveRecord::RecordNotFound, 'Shard user not found' unless ship_shard_user
      raise ValidationError, 'Ship does not belong to this shard' unless ship_shard_user.shard_id == shard.id
    end

    def self.create_user_ship_for_status!(ship_guid:, ship:, shard:, shard_user:, user:)
      user_ship = UserShip.find_or_initialize_by(guid: ship_guid)
      return user_ship unless user_ship.new_record?

      user_ship.assign_attributes(
        user: user,
        ship: ship,
        shard: shard,
        shard_user: shard_user,
        ship_slug: ship.slug,
        shard_name: shard.name,
        location_name: default_location_name_for_status,
        total_scu: total_scu_for_ship(ship),
        used_scu: 0,
        status: 'docked'
      )
      user_ship.save!
      user_ship
    rescue ActiveRecord::RecordNotUnique
      UserShip.find_by!(guid: ship_guid)
    end

    def self.default_location_name_for_status
      Location.find_by(name: 'Orison')&.name
    end

    def self.total_scu_for_ship(ship)
      return ship.total_scu if ship.respond_to?(:total_scu) && ship.total_scu.present?
      return ship.scu if ship.respond_to?(:scu) && ship.scu.present?
      return ship.cargo_capacity if ship.respond_to?(:cargo_capacity) && ship.cargo_capacity.present?

      0
    end

    def self.status_response_for(shard_user:, user_ship:, wallet_balance:, request_id: nil)
      update_status_wallet_balance!(shard_user, wallet_balance)

      return no_ship_status_response(shard_user) if user_ship.nil?

      current_tick = Tick.current
      active_travel = active_status_travel(user_ship, current_tick)
      availability = status_availability_for(
        shard_user: shard_user,
        user_ship: user_ship,
        active_travel: active_travel
      )
      user_ship.reload
      user_ship.touch

      cargo = user_ship_cargo_json(user_ship)
      ship_travel = active_travel || latest_relevant_ship_travel(user_ship)

      response = {
        status: 'success',
        wallet_balance: shard_user.wallet_balance,
        player_location: availability.player_location&.name,
        ship: {
          model: user_ship.ship.model,
          location: user_ship.location_name,
          available_at_player_location: availability.available,
          unavailable_reason: availability.reason,
          total_scu: user_ship.total_scu,
          used_scu: user_ship.used_scu,
          available_cargo_space: user_ship.available_cargo_space,
          travel_status: user_ship.status,
          from_location: ship_travel&.from_location&.name,
          to_location: ship_travel&.to_location&.name,
          arrival_tick: ship_travel&.arrival_tick,
          current_tick: current_tick,
          time_remaining: ship_travel&.seconds_remaining(current_tick)
        },
        ships: ships_availability_json(shard_user),
        cargo: cargo,
      }

      if active_travel
        travel_payload = status_travel_payload(active_travel, current_tick)
        Rails.logger.info(
          "[TradeService.status] active_travel_detected " \
          "request_id=#{request_id.inspect} user_ship_id=#{user_ship.id.inspect} " \
          "ship_guid=#{user_ship.guid.inspect} active_travel_id=#{active_travel.id.inspect} " \
          "travel_guid=#{active_travel.travel_guid.inspect} " \
          "from_location=#{travel_payload[:from_location].inspect} " \
          "to_location=#{travel_payload[:to_location].inspect} " \
          "current_tick=#{current_tick.inspect} arrival_tick=#{active_travel.arrival_tick.inspect} " \
          "remaining_ticks=#{travel_payload[:remaining_ticks].inspect}"
        )

        response.merge!(
          ship_status: 'in_transit',
          message: 'Ship is currently in transit.',
          ship_guid: user_ship.guid,
          ship_model: user_ship.ship&.model,
          current_location: availability.ship_location&.name || user_ship.location_name,
          travel: travel_payload
        )
      end

      response
    end

    def self.status_availability_for(shard_user:, user_ship:, active_travel:)
      player_location = shard_user.current_location
      ship_location = user_ship.location || Location.find_by(name: user_ship.location_name)
      player_location ||= ship_location

      reason =
        if active_travel
          "Ship is currently in transit."
        elsif player_location.nil?
          "Player location is unknown; initialize current location before switching ships."
        elsif ship_location.nil?
          "Ship location is unknown; initialize the ship location before use."
        elsif ship_location.id != player_location.id
          "Ship is at #{ship_location.name}, but player is at #{player_location.name}."
        end

      ShipAvailability::Result.new(
        available: reason.nil?,
        reason: reason,
        player_location: player_location,
        ship_location: ship_location,
        in_transit: active_travel.present?
      )
    end

    def self.active_status_travel(user_ship, current_tick = Tick.current)
      user_ship.ship_travels
               .where(completed_at_tick: nil)
               .where("is_paused = ? OR arrival_tick > ?", true, current_tick)
               .order(updated_at: :desc)
               .first
    end

    def self.status_travel_payload(travel, current_tick = Tick.current)
      remaining_ticks = if travel.is_paused?
                          travel.remaining_ticks_from_arrival.to_i
                        else
                          [travel.arrival_tick.to_i - current_tick.to_i, 0].max
                        end

      {
        travel_guid: travel.travel_guid,
        from_location: travel.from_location&.name,
        to_location: travel.to_location&.name,
        departure_tick: travel.departure_tick,
        arrival_tick: travel.arrival_tick,
        current_tick: current_tick,
        remaining_ticks: remaining_ticks,
        time_remaining: remaining_ticks * Tick.seconds_per_tick,
        is_paused: travel.is_paused
      }
    end

    def self.latest_relevant_ship_travel(user_ship)
      user_ship.ship_travels
               .where(completed_at_tick: nil)
               .order(updated_at: :desc)
               .first ||
        user_ship.ship_travels.order(created_at: :desc).first
    end

    def self.ships_availability_json(shard_user)
      shard_user.user_ships.includes(:ship).order(updated_at: :desc).map do |ship_record|
        availability = status_availability_for(
          shard_user: shard_user,
          user_ship: ship_record,
          active_travel: active_status_travel(ship_record)
        )

        {
          guid: ship_record.guid,
          model: ship_record.ship&.model,
          ship_slug: ship_record.ship_slug.presence || ship_record.ship&.slug,
          location: availability.ship_location&.name || ship_record.location_name,
          travel_status: ship_record.status,
          in_transit: availability.in_transit,
          available_at_player_location: availability.available,
          unavailable_reason: availability.reason
        }
      end
    end

    def self.update_status_wallet_balance!(shard_user, wallet_balance)
      validate_wallet_balance!(wallet_balance)
      shard_user.update!(wallet_balance: wallet_balance) if wallet_balance.present?
      shard_user.update!(wallet_balance: 15000) if shard_user.wallet_balance == 0
    end

    def self.no_ship_status_response(shard_user)
      {
        status: 'success',
        wallet_balance: shard_user.wallet_balance,
        ship: "No Ship",
        cargo: []
      }
    end

    def self.validate_wallet_balance!(wallet_balance)
      return if wallet_balance.blank?
      return if wallet_balance.is_a?(Numeric)
      return if wallet_balance.to_s.match?(/\A-?\d+(\.\d+)?\z/)

      raise ValidationError, 'wallet_balance must be numeric'
    end

    def self.user_ship_cargo_json(user_ship)
      user_ship.user_ship_cargos.includes(:commodity).map do |cargo_item|
        {
          commodity_name: cargo_item.commodity&.name || cargo_item.commodity_name,
          scu: cargo_item.scu
        }
      end
    end

    def self.trade_debug(message, context = {})
      Rails.logger.info("[TradeDebug] #{message} #{trade_debug_context(context)}")
    end

    def self.trade_debug_warn(message, context = {})
      Rails.logger.warn("[TradeDebug] #{message} #{trade_debug_context(context)}")
    end

    def self.trade_debug_error(message, context = {})
      Rails.logger.error("[TradeDebug] #{message} #{trade_debug_context(context)}")
    end

    def self.trade_debug_context(context)
      context.compact.map { |key, value| "#{key}=#{trade_debug_value(value)}" }.join(' ')
    rescue StandardError => e
      "debug_context_error=#{e.class.name.inspect} debug_context_error_message=#{e.message.inspect}"
    end

    def self.trade_debug_value(value)
      case value
      when ActiveRecord::Base
        "#<#{value.class.name} id=#{value.id.inspect}>".inspect
      else
        value.inspect
      end
    rescue StandardError => e
      "#<debug_value_error #{e.class.name}: #{e.message}>".inspect
    end

    def self.trade_debug_input_summary(username:, commodity_name: nil, scu: nil, shard: nil, ship_guid: nil, ship_slug: nil, wallet_balance: nil, request_id: nil)
      {
        request_id: request_id,
        username: username,
        commodity_name: commodity_name,
        scu: scu,
        shard: shard,
        ship_guid: ship_guid,
        ship_slug: ship_slug,
        wallet_balance_present: wallet_balance.present?
      }
    end

    def self.safe_record_value(record, attribute)
      return nil unless record&.respond_to?(attribute)

      record.public_send(attribute)
    rescue StandardError => e
      "debug_error:#{e.class.name}"
    end

    def self.safe_relation_count(record, association)
      return nil unless record&.respond_to?(association)

      record.public_send(association).count
    rescue StandardError => e
      "debug_error:#{e.class.name}"
    end

    def self.trade_debug_user_summary(user)
      {
        user_found: user.present?,
        user_id: user&.id,
        username: user&.username,
        twitch_id_present: user&.twitch_id.present?,
        shard_users_count: safe_relation_count(user, :shard_users)
      }
    end

    def self.trade_debug_shard_user_summary(shard_user)
      {
        shard_user_found: shard_user.present?,
        shard_user_id: shard_user&.id,
        shard_user_shard_id: shard_user&.shard_id,
        shard_user_shard_name: shard_user&.shard_name,
        wallet_balance: shard_user&.wallet_balance,
        user_ship_count: safe_relation_count(shard_user, :user_ships)
      }
    end

    def self.trade_debug_shard_users_for(user)
      return [] unless user

      user.shard_users.map do |candidate|
        {
          id: candidate.id,
          shard_id: candidate.shard_id,
          shard_name: candidate.shard_name,
          wallet_balance: candidate.wallet_balance,
          user_ships_count: safe_relation_count(candidate, :user_ships)
        }
      end
    rescue StandardError => e
      [{ debug_error: e.class.name, message: e.message }]
    end

    def self.trade_debug_user_ship_summary(user_ship)
      {
        user_ship_found: user_ship.present?,
        user_ship_id: user_ship&.id,
        guid: user_ship&.guid,
        ship_id: user_ship&.ship_id,
        ship_slug: safe_record_value(user_ship, :ship_slug),
        location_name: user_ship&.location_name,
        total_scu: user_ship&.total_scu,
        used_scu: user_ship&.used_scu,
        available_cargo_space: safe_record_value(user_ship, :available_cargo_space),
        status: user_ship&.status
      }
    end

    def self.trade_debug_facility_summary(facility)
      {
        facility_id: facility&.id,
        location_name: facility&.location_name,
        commodity_name: facility&.commodity_name,
        inventory: safe_record_value(facility, :inventory),
        price_buy: safe_record_value(facility, :price_buy),
        local_buy_price: safe_record_value(facility, :local_buy_price),
        status_buy: safe_record_value(facility, :status_buy),
        status_sell: safe_record_value(facility, :status_sell),
        production_rate: safe_record_value(facility, :production_rate),
        consumption_rate: safe_record_value(facility, :consumption_rate)
      }.compact
    end


    def self.buy(username:, wallet_balance:, commodity_name:, scu:, shard:, ship_guid:, ship_slug:, request_id: nil)
      input_summary = trade_debug_input_summary(
        username: username,
        commodity_name: commodity_name,
        scu: scu,
        shard: shard,
        ship_guid: ship_guid,
        ship_slug: ship_slug,
        wallet_balance: wallet_balance,
        request_id: request_id
      )
      trade_debug('TradeService.buy entry', input_summary)

      normalized_username = username.downcase
      trade_debug('TradeService.buy before user lookup', input_summary.merge(normalized_username: normalized_username))
      user_relation = User.where("LOWER(username) = ?", normalized_username)
      user = user_relation.first
      trade_debug('TradeService.buy after user lookup', input_summary.merge(trade_debug_user_summary(user)))
      user ||= user_relation.first!

      trade_debug('TradeService.buy before commodity lookup', input_summary.merge(requested_commodity_name: commodity_name))
      commodity_relation = Commodity.where("name ILIKE ?", commodity_name)
      commodity = commodity_relation.first
      trade_debug(
        'TradeService.buy after commodity lookup',
        input_summary.merge(
          commodity_found: commodity.present?,
          commodity_id: commodity&.id,
          commodity_name: commodity&.name,
          is_sellable: commodity&.is_sellable
        )
      )
      commodity ||= commodity_relation.first!

      requested_shard_uuid = shard
      trade_debug('TradeService.buy before shard lookup', input_summary.merge(requested_shard_uuid: requested_shard_uuid))
      shard = Shard.find_by(channel_uuid: shard)
      trade_debug(
        'TradeService.buy after shard lookup',
        input_summary.merge(
          shard_found: shard.present?,
          shard_id: shard&.id,
          shard_name: shard&.name,
          channel_uuid: shard&.channel_uuid
        )
      )

      shard_name = shard.name
      trade_debug(
        'TradeService.buy before shard_user lookup',
        input_summary.merge(
          user_id: user.id,
          shard_id: shard&.id,
          shard_name: shard_name,
          lookup_condition: 'LOWER(shard_name) = shard_name.downcase',
          available_shard_users: trade_debug_shard_users_for(user)
        )
      )
      shard_user = user.shard_users.where("LOWER(shard_name) = ?", shard_name.downcase).first
      trade_debug('TradeService.buy after shard_user lookup', input_summary.merge(trade_debug_shard_user_summary(shard_user)))
      raise ShipNotFoundError, "No ship found for user '#{username}'." if shard_user.nil?

      trade_debug(
        'TradeService.buy before shard_user.update',
        input_summary.merge(
          about_to_update_shard_user: true,
          shard_user_nil: shard_user.nil?,
          wallet_balance_class: wallet_balance.class.name
        )
      )
      wallet_update_result = shard_user.update(wallet_balance:wallet_balance)
      trade_debug(
        'TradeService.buy after shard_user.update',
        input_summary.merge(
          wallet_update_result: wallet_update_result,
          wallet_balance_after_update: shard_user&.wallet_balance,
          validation_errors: (shard_user&.errors&.full_messages if wallet_update_result == false)
        )
      )
     
      trade_debug(
        'TradeService.buy before resolve_trade_ship',
        input_summary.merge(
          user_id: user.id,
          shard_user_id: shard_user&.id,
          shard_id: shard&.id,
          create_missing: true
        )
      )
      user_ship = resolve_trade_ship(
        user: user,
        shard_user: shard_user,
        shard: shard,
        ship_guid: ship_guid,
        ship_slug: ship_slug,
        create_missing: true
      )
      trade_debug('TradeService.buy after resolve_trade_ship', input_summary.merge(trade_debug_user_ship_summary(user_ship)))
      

      if shard_user.wallet_balance == 0
        raise InsufficientCreditsError, "INSF FNDS '#{username}'."
      end
      
      trade_location_names_for_debug = trade_location_names(user_ship.location_name)
      trade_debug(
        'TradeService.buy before facility resolution',
        input_summary.merge(
          user_ship_location_name: user_ship.location_name,
          resolved_trade_location_names: trade_location_names_for_debug
        )
      )
      candidate_facilities = buyable_facilities_for_trade_location(user_ship.location_name).to_a
      trade_debug(
        'TradeService.buy candidate facilities',
        input_summary.merge(
          candidate_facility_count: candidate_facilities.count,
          candidate_facilities: candidate_facilities.map { |candidate| trade_debug_facility_summary(candidate) }
        )
      )
      facility = candidate_facilities.find { |candidate| candidate.commodity_name.to_s.casecmp?(commodity.name) }
      trade_debug('TradeService.buy selected facility', input_summary.merge(selected_facility_id: facility&.id))
      location_name = facility&.location_name.presence || trade_facility_location_name(user_ship.location_name, candidate_facilities)

      if facility.nil?
        raise InsufficientInventoryError, "No matching facility found for #{location_name} and #{commodity.name}."
      elsif facility.inventory <= 0
        raise InsufficientInventoryError, "#{facility.location_name} Facility does not have enough inventory to sell."
      end

      original_scu = scu
      if scu == "max"
        scu = ""
      end

      # ✅ Calculate the maximum affordable SCU based on wallet and cargo space
      buy_price = player_buy_price(facility)
      max_affordable_scu = (shard_user.wallet_balance.to_d / buy_price.to_d).floor
      max_cargo_space = user_ship.available_cargo_space
      max_facility_inventory = facility.inventory
    
      if max_cargo_space <= 0
        raise InsufficientCapacityError, "No cargo space"
      end

      # ✅ Default SCU to the maximum possible if not provided or if too large
      scu = [scu.to_i, max_affordable_scu, max_cargo_space, max_facility_inventory].select { |v| v > 0 }.min
      raise InsufficientInventoryError, "Not enough cargo inventory at facility. Available: #{facility.inventory} SCU." if scu > facility.inventory
    
      total_cost = transaction_total_capital(scu: scu, unit_price: buy_price)
      loading_time_seconds = loading_time_seconds_for_scu(scu)
      loading_ticks = loading_ticks_for_scu(scu)
      trade_debug(
        'TradeService.buy SCU and pricing',
        input_summary.merge(
          original_scu: original_scu,
          normalized_scu: scu,
          buy_price: buy_price,
          max_affordable_scu: max_affordable_scu,
          max_cargo_space: max_cargo_space,
          max_facility_inventory: max_facility_inventory,
          final_scu: scu,
          total_cost: total_cost,
          loading_time_seconds: loading_time_seconds,
          loading_ticks: loading_ticks
        )
      )
    
      # ✅ Validate Commodity Availability
      raise CommodityNotAvailableError, "Commodity not available at this location." unless facility.commodity.is_sellable
    

      # ✅ Perform Transaction
      ActiveRecord::Base.transaction do
        wallet_before_credits = shard_user.wallet_balance
        trade_debug('TradeService.buy transaction before shard_user.update_credits', input_summary.merge(shard_user_id: shard_user.id, wallet_balance_before: wallet_before_credits, credits_delta: -total_cost))
        shard_user.update_credits(-total_cost)
        trade_debug('TradeService.buy transaction after shard_user.update_credits', input_summary.merge(shard_user_id: shard_user.id, wallet_balance_before: wallet_before_credits, wallet_balance_after: shard_user.reload.wallet_balance))
    
        trade_debug('TradeService.buy transaction before cargo find_or_initialize', input_summary.merge(user_ship_id: user_ship.id, commodity_id: commodity.id))
        cargo = user_ship.user_ship_cargos.find_or_initialize_by(commodity_id: commodity.id)
        cargo_scu_before = cargo.scu
        cargo_new_record = cargo.new_record?
        trade_debug('TradeService.buy transaction after cargo find_or_initialize', input_summary.merge(cargo_id: cargo.id, cargo_new_record: cargo_new_record, cargo_scu_before: cargo_scu_before))
        cargo.scu = cargo.scu.to_i + scu
        cargo.buy_price = buy_price
        cargo.commodity_name = commodity.name
        trade_debug('TradeService.buy transaction before cargo save', input_summary.merge(cargo_id: cargo.id, cargo_scu_before: cargo_scu_before, cargo_scu_after: cargo.scu, buy_price: buy_price))
        cargo.save!
        trade_debug('TradeService.buy transaction after cargo save', input_summary.merge(cargo_id: cargo.id, cargo_scu_after: cargo.scu))

        trade_debug(
          'TradeService.buy transaction before StarBitizenRun lookup',
          input_summary.merge(user_id: user.id, user_ship_id: user_ship.id, commodity_name: commodity.name, buy_location_name: location_name, shard_id: shard&.id)
        )
        star_bitizen_run = StarBitizenRun.find_by(
          user: user,
          user_ship: user_ship,
          commodity_name: commodity.name,
          buy_location_name: location_name,
          shard: shard_name,
          local_sell_price: nil
        )
        trade_debug('TradeService.buy transaction after StarBitizenRun lookup', input_summary.merge(star_bitizen_run_id: star_bitizen_run&.id, star_bitizen_run_found: star_bitizen_run.present?))

        if star_bitizen_run
          star_bitizen_run_scu_before = star_bitizen_run.scu
          trade_debug('TradeService.buy transaction before StarBitizenRun update', input_summary.merge(star_bitizen_run_id: star_bitizen_run.id, scu_before: star_bitizen_run_scu_before, scu_delta: scu, local_buy_price: buy_price))
          # ✅ Update existing StarBitizenRun record
          star_bitizen_run.update!(
            local_buy_price: buy_price, # Update to latest buy price
            scu: star_bitizen_run.scu + scu, # Add to existing SCU
            profit: 0 # Reset profit until sold
          )
          trade_debug('TradeService.buy transaction after StarBitizenRun update', input_summary.merge(star_bitizen_run_id: star_bitizen_run.id, scu_before: star_bitizen_run_scu_before, scu_after: star_bitizen_run.scu))
        else
          trade_debug('TradeService.buy transaction before StarBitizenRun create', input_summary.merge(user_id: user.id, user_ship_id: user_ship.id, cargo_id: user_ship.user_ship_cargos.last&.id, scu: scu, local_buy_price: buy_price))
          # ✅ Create new StarBitizenRun record if none exists
          star_bitizen_run = StarBitizenRun.create!(
            user: user,
            commodity: commodity,
            commodity_name: commodity.name,
            local_buy_price: buy_price,
            local_sell_price: nil, # Will be updated later
            scu: scu,
            buy_location_name: location_name,
            sell_location_name: nil, # Will be updated later
            profit: 0,
            user_ship_cargo_id: user_ship.user_ship_cargos.last.id,
            user_ship_id: user_ship.id,
            shard: shard_name # Track game shard
          )
          trade_debug('TradeService.buy transaction after StarBitizenRun create', input_summary.merge(star_bitizen_run_id: star_bitizen_run.id, scu: star_bitizen_run.scu))
        end

        facility_inventory_before = facility.inventory
        trade_debug('TradeService.buy transaction before facility inventory update', input_summary.merge(facility_id: facility.id, inventory_before: facility_inventory_before, scu_delta: -scu))
        facility.update!(inventory: facility.inventory - scu)
        trade_debug('TradeService.buy transaction after facility inventory update', input_summary.merge(facility_id: facility.id, inventory_before: facility_inventory_before, inventory_after: facility.inventory))
      end

      user_ship_cargo = user_ship.user_ship_cargos.last
      trade_debug('TradeService.buy after transaction', input_summary.merge(user_ship_cargo_id: user_ship_cargo&.id, wallet_balance: shard_user.reload.wallet_balance))

    
      # ✅ Return API Response
      {
        status: 'success',
        wallet_balance: shard_user.wallet_balance,
        loading_time: loading_time_seconds,
        loading_ticks: loading_ticks,
        scu: scu,
        capital: total_cost.to_f,
        total_capital: total_cost.to_f,
        message: "Purchased #{scu} SCU of #{commodity_name} at #{location_name}"
      }
    rescue StandardError => e
      trade_debug_error(
        'TradeService.buy failed',
        (defined?(input_summary) && input_summary ? input_summary : {}).merge(
          error_class: e.class.name,
          error_message: e.message,
          backtrace: e.backtrace&.join("\n")
        )
      )
      raise
    end    

   # I need to build something that can split a starbitizenrun if they decided to split their cargo.

    def self.sell(username:, wallet_balance:, commodity_name: nil, scu: nil, shard:)
      user = User.where("LOWER(username) = ?", username.downcase).first!
      
      shard = Shard.find_by(channel_uuid: shard)
      
      shard_name = shard.name  
      shard_user = user.shard_users.where("LOWER(shard_name) = ?", shard_name.downcase).first
    
      user_ship = shard_user.user_ships.order(updated_at: :desc).first
      raise ShipNotFoundError, "No ship found for user '#{username}'." unless user_ship
    
      shard_user.update!(wallet_balance: wallet_balance)
    
      location_name = user_ship.location_name
      location = Location.find_by!(name: location_name)

      # ✅ Find the specified commodity
      commodity = Commodity.where("name ILIKE ?", commodity_name).first!

      facility = facilities_buying_from_player
        .where("location_name ILIKE ? AND commodity_name = ?", "%#{location.name}%", commodity.name)
        .first

      if facility.nil?
        raise InsufficientInventoryError, "No matching facility found for #{location.name} and #{commodity.name}."
      elsif facility.inventory == facility.max_inventory
        raise InsufficientInventoryError, "#{facility.location_name} Facility does not have enough inventory to sell."
      end
    
      cargo_to_sell = user_ship.user_ship_cargos.find_by(commodity_id: commodity.id)
      raise InsufficientInventoryError, "No inventory of #{commodity_name} to sell." if cargo_to_sell.nil?
    
    max_scu = (scu.blank? || scu.to_i <= 0) ? cargo_to_sell.scu : scu.to_i
      max_facility_demand = facility_buy_capacity(facility) || cargo_to_sell.scu
      scu_to_sell = [max_scu, max_facility_demand].select { |v| v > 0 }.min
    
      raise InsufficientInventoryError, "Not enough inventory to sell. You have #{cargo_to_sell.scu} SCU of #{commodity_name}." if cargo_to_sell.scu < scu_to_sell
    
      # ✅ Calculate Profit
      sell_price = player_sell_price(facility)
      total_revenue = transaction_total_capital(scu: scu_to_sell, unit_price: sell_price)
    
      ActiveRecord::Base.transaction do
        
        shard_user.update_credits(total_revenue)
    
        cargo_to_sell.scu -= scu_to_sell

        star_bitizen_run = StarBitizenRun.find_by(
          user: user,
          user_ship: user_ship,
          commodity_name: cargo_to_sell.commodity.name,
          local_sell_price: nil,
          shard: shard_name
        )

                # Update trade record
                if star_bitizen_run.present?
                  star_bitizen_run.update!(
                    local_sell_price: sell_price,
                    sell_location_name: location.name,
                    profit: ShardUser.credit_amount(total_revenue),
                    scu: scu_to_sell
                  )
                end

        cargo_to_sell.scu <= 0 ? cargo_to_sell.destroy! : cargo_to_sell.save!

        facility.update!(inventory: [facility.inventory + scu_to_sell, facility.max_inventory].min)
      end
    
      # ✅ Return API Response
      {
        status: 'success',
        profit: total_revenue.to_f,
        capital: total_revenue.to_f,
        total_capital: total_revenue.to_f,
        wallet_balance: shard_user.wallet_balance,
        scu: scu_to_sell,
        message: "Sold #{scu_to_sell} SCU of #{commodity_name} at #{location_name}"
      }
    end

    def self.list_sellable_commodities(username:, shard:)
      user = User.where("LOWER(username) = ?", username.downcase).first!
      shard_user = user.shard_users.where("LOWER(shard_name) = ?", shard.downcase).first
      raise ShipNotFoundError, "No ship found for user '#{username}'." if shard_user.nil?

      user_ship = shard_user.user_ships.order(updated_at: :desc).first
      raise ShipNotFoundError, "No ship found for user '#{username}'." unless user_ship

      location_name = user_ship.location_name
      location = Location.where("name ILIKE ?", "%#{location_name}%").first!

      commodities = facilities_selling_to_player_for_sell_command
        .where("location_name ILIKE ?", "%#{location.name}%")
        .map do |facility|
          {
            commodity_name: facility.commodity_name,
            sell_price: player_sell_price(facility),
            scu: facility.scu_sell_stock
          }
        end

      if commodities.empty?
        return {
          status: 'error',
          message: "No commodities can be sold at #{location_name}.",
          location: location_name,
          commodities: []
        }
      end

      {
        status: 'success',
        message: "Commodities available to sell at #{location_name}.",
        location: location_name,
        commodities: commodities
      }
    end

    def self.find_or_create_user(username, shard)
        raise ValidationError, 'username is required' if username.blank?
        raise ActiveRecord::RecordNotFound, 'Shard not found' unless shard

        normalized_username = username.to_s.downcase.strip
        
        # ✅ Find user case-insensitively
        user = User.where("LOWER(username) = ?", normalized_username).first
         
        # ✅ Create user only if not found
        unless user
          user = User.create!(
            username: normalized_username,
            uid: SecureRandom.hex(10),
            twitch_id: SecureRandom.hex(10),
            user_type: "player",
            provider: "twitch"
          )
        end
        

        unless user.shard_users.find_by(shard_id: shard.id)

          ShardUser.create!(user_id: user.id, shard_id: shard.id, shard_name: shard.name)
          
        end

        user
      end
      

      def self.list_available_commodities(username:, shard_uuid: nil, shard: nil, ship_guid: nil, ship_slug: nil, request_id: nil)
        requested_shard = shard_uuid.presence || shard
        input_summary = trade_debug_input_summary(
          username: username,
          shard: requested_shard,
          ship_guid: ship_guid,
          ship_slug: ship_slug,
          request_id: request_id
        )
        trade_debug('TradeService.list_available_commodities entry', input_summary)

        trade_debug('TradeService.list_available_commodities before shard lookup', input_summary.merge(requested_shard: requested_shard))
        shard = find_trade_shard(requested_shard)
        trade_debug(
          'TradeService.list_available_commodities after shard lookup',
          input_summary.merge(
            shard_found: shard.present?,
            shard_id: shard&.id,
            shard_name: shard&.name,
            channel_uuid: shard&.channel_uuid
          )
        )
        raise ActiveRecord::RecordNotFound, 'Shard not found' if shard.nil?

        shard_name = shard.name

        normalized_username = username.downcase
        trade_debug('TradeService.list_available_commodities before user lookup', input_summary.merge(normalized_username: normalized_username))
        user_relation = User.where("LOWER(username) = ?", normalized_username)
        user = user_relation.first
        trade_debug('TradeService.list_available_commodities after user lookup', input_summary.merge(trade_debug_user_summary(user)))
        user ||= user_relation.first!

        trade_debug(
          'TradeService.list_available_commodities before shard_user lookup',
          input_summary.merge(
            user_id: user.id,
            shard_id: shard&.id,
            shard_name: shard_name,
            lookup_condition: 'LOWER(shard_name) = shard_name.downcase',
            available_shard_users: trade_debug_shard_users_for(user)
          )
        )
        shard_user = user.shard_users.where("LOWER(shard_name) = ?", shard_name.downcase).first
        trade_debug('TradeService.list_available_commodities after shard_user lookup', input_summary.merge(trade_debug_shard_user_summary(shard_user)))

        trade_debug(
          'TradeService.list_available_commodities before listing location resolution',
          input_summary.merge(
            user_id: user.id,
            shard_user_id: shard_user&.id,
            shard_id: shard&.id,
            create_missing: false
          )
        )
        listing_location = resolve_listing_trade_location(
          user: user,
          shard_user: shard_user,
          shard: shard,
          ship_guid: ship_guid,
          ship_slug: ship_slug
        )
        trade_debug(
          'TradeService.list_available_commodities after listing location resolution',
          input_summary.merge(
            location_name: listing_location[:location_name],
            location_source: listing_location[:source],
            user_ship_id: listing_location[:user_ship]&.id,
            shard_user_id: listing_location[:shard_user]&.id
          )
        )
        raise ShipNotFoundError, "No ship found for user '#{username}'." if listing_location[:location_name].blank?

        location_name = listing_location[:location_name]
        trade_location_names_for_debug = trade_location_names(location_name)
        trade_debug(
          'TradeService.list_available_commodities before facility lookup',
          input_summary.merge(
            listing_location_name: location_name,
            listing_location_source: listing_location[:source],
            resolved_trade_location_names: trade_location_names_for_debug
          )
        )
        commodities = buyable_facilities_for_trade_location(location_name).includes(:commodity).to_a
        trade_debug(
          'TradeService.list_available_commodities facilities found',
          input_summary.merge(
            candidate_facility_count: commodities.count,
            candidate_facilities: commodities.map { |facility| trade_debug_facility_summary(facility) }
          )
        )
        response_location_name = trade_facility_location_name(location_name, commodities)

        commodities = commodities.map do |facility|
          {
            commodity_name: facility.commodity.name,
            price: player_buy_price(facility)
          }
        end
        trade_debug('TradeService.list_available_commodities response commodity count', input_summary.merge(returned_commodity_count: commodities.count, response_location_name: response_location_name))

        if commodities.empty?
          return {
            status: 'error',
            message: "No commodities available for purchase at #{response_location_name}.",
            location: response_location_name,
            commodities: []
          }
        end

        {
          status: 'success',
          message: "Commodities available for purchase at #{response_location_name}.",
          location: response_location_name,
          commodities: commodities
        }
      rescue StandardError => e
        trade_debug_error(
          'TradeService.list_available_commodities failed',
          (defined?(input_summary) && input_summary ? input_summary : {}).merge(
            error_class: e.class.name,
            error_message: e.message,
            backtrace: e.backtrace&.join("\n")
          )
        )
        raise
      end

      def self.facilities_selling_to_player
        ProductionFacility.where("COALESCE(NULLIF(local_buy_price, 0), NULLIF(price_buy, 0), 0) > 0")
      end

      def self.facilities_buying_from_player
        ProductionFacility
          .where("consumption_rate > 0")
          .where("status_sell > 0")
          .where("COALESCE(price_sell, 0) > 0 OR COALESCE(local_sell_price, 0) > 0")
      end

      def self.facilities_selling_to_player_for_sell_command
        ProductionFacility
          .where("status_sell > 0")
          .where("COALESCE(price_sell, 0) > 0 OR COALESCE(local_sell_price, 0) > 0")
      end

      def self.player_buy_price(facility)
        facility.local_buy_price.to_d.positive? ? facility.local_buy_price : facility.price_buy
      end

      def self.player_sell_price(facility)
        facility.local_sell_price.to_d.positive? ? facility.local_sell_price : facility.price_sell
      end

      def self.facility_buy_capacity(facility)
        return nil if facility.max_inventory.to_i.zero?
        facility.max_inventory.to_i - facility.inventory.to_i
      end

      def self.resolve_trade_ship(user:, shard_user:, shard:, ship_guid: nil, ship_slug: nil, create_missing: false)
        user_ship = shard_user.user_ships.find_by(guid: ship_guid) if ship_guid.present?
        return user_ship if user_ship.present?
        return shard_user.user_ships.order(updated_at: :desc).first unless create_missing

        raise ActiveRecord::RecordInvalid, "ship_slug is required when ship_guid not found." if ship_slug.blank?

        ship = Ship.find_by!(slug: ship_slug)
        new_ship_location = Location.find_by_name("Orison")&.name
        raise LocationMismatchError, "location_name required to create ship (no prior ship to infer from)." if new_ship_location.blank?

        shard_user.user_ships.create!(
          guid: ship_guid.presence || SecureRandom.uuid,
          ship: ship,
          ship_slug: ship.slug,
          shard: shard,
          shard_user: shard_user,
          user: user,
          total_scu: ship.scu,
          used_scu: 0,
          location_name: new_ship_location
        )
      end

      def self.find_trade_shard(shard_identifier)
        normalized = shard_identifier.to_s.strip
        return if normalized.blank?

        Shard.find_by(channel_uuid: normalized) ||
          Shard.where("LOWER(name) = ?", normalized.downcase).first
      end

      def self.resolve_listing_trade_location(user:, shard_user:, shard:, ship_guid: nil, ship_slug: nil)
        user_ship = find_listing_user_ship(
          user: user,
          shard_user: shard_user,
          shard: shard,
          ship_guid: ship_guid,
          ship_slug: ship_slug
        )
        return { location_name: user_ship.location_name, source: 'user_ship', user_ship: user_ship, shard_user: shard_user } if user_ship&.location_name.present?

        if shard_user&.current_location_name.present?
          return {
            location_name: shard_user.current_location_name,
            source: 'shard_user_current_location',
            user_ship: user_ship,
            shard_user: shard_user
          }
        end

        if ship_slug.present? && Ship.exists?(slug: ship_slug)
          fallback_location_name = default_listing_location_name
          if fallback_location_name.present?
            return {
              location_name: fallback_location_name,
              source: 'ship_definition_fallback',
              user_ship: user_ship,
              shard_user: shard_user
            }
          end
        end

        { location_name: nil, source: 'unresolved', user_ship: user_ship, shard_user: shard_user }
      end

      def self.find_listing_user_ship(user:, shard_user:, shard:, ship_guid: nil, ship_slug: nil)
        if ship_guid.present?
          user_ship = user.user_ships.find_by(guid: ship_guid)
          return user_ship if user_ship.present?
        end

        user_ship = shard_user&.user_ships&.order(updated_at: :desc)&.first
        return user_ship if user_ship.present?

        user_ship = user.user_ships.where(shard_id: shard.id).order(updated_at: :desc).first if shard.present?
        return user_ship if user_ship.present?

        user.user_ships.where(ship_slug: ship_slug).order(updated_at: :desc).first if ship_slug.present?
      end

      def self.default_listing_location_name
        default_location_name_for_status.presence ||
          facilities_selling_to_player.where.not(location_name: [nil, '']).order(:location_name).pick(:location_name)
      end

      def self.buyable_facilities_for_trade_location(location_name)
        facilities_selling_to_player
          .where("LOWER(location_name) IN (?)", trade_location_names(location_name).map(&:downcase))
          .includes(:commodity)
      end

      def self.trade_location_names(location_name)
        location = resolved_trade_location(location_name)
        names = [location.name]

        child_locations = Location.where(
          "LOWER(parent_name) = :name OR LOWER(planet_name) = :name OR LOWER(moon_name) = :name",
          name: location.name.downcase
        )
        names.concat(child_locations.pluck(:name))
        names.compact_blank.uniq
      end

      def self.resolved_trade_location(location_name)
        Location.find_by!("LOWER(name) = ?", location_name.to_s.downcase)
      rescue ActiveRecord::RecordNotFound
        Location.where("name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(location_name.to_s)}%").first!
      end

      def self.trade_facility_location_name(default_location_name, facilities)
        facility_location_names = facilities.map(&:location_name).compact_blank.uniq
        return facility_location_names.first if facility_location_names.one?

        resolved_trade_location(default_location_name).name
      end

      def self.transaction_total_capital(scu:, unit_price:)
        (scu.to_d * unit_price.to_d).round(2)
      end

      def self.loading_time_seconds_for_scu(scu)
        loading_ticks_for_scu(scu) * Tick.seconds_per_tick
      end

      def self.loading_ticks_for_scu(scu)
        (scu.to_i * loading_ticks_per_scu) + base_loading_ticks
      end

      def self.base_loading_ticks = BASE_LOADING_TICKS

      def self.loading_ticks_per_scu = LOADING_TICKS_PER_SCU


  end
  
