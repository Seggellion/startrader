
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
  
    def self.status(ship_guid: nil, shard_uuid: nil, wallet_balance: nil, username: nil, shard: nil)
      has_new_payload = ship_guid.present? || shard_uuid.present?

      Rails.logger.info(
        "[TradeService.status] path=#{has_new_payload ? 'ship_guid' : 'legacy'} " \
        "ship_guid_present=#{ship_guid.present?} shard_uuid_present=#{shard_uuid.present?} " \
        "username_present=#{username.present?} shard_present=#{shard.present?}"
      )

      if has_new_payload
        raise ValidationError, 'ship_guid is required' if ship_guid.blank?
        raise ValidationError, 'shard_uuid is required' if shard_uuid.blank?

        return status_by_ship_guid(
          ship_guid: ship_guid,
          shard_uuid: shard_uuid,
          wallet_balance: wallet_balance
        )
      end

      raise ValidationError, 'username is required for legacy status' if username.blank?
      raise ValidationError, 'shard is required for legacy status' if shard.blank?

      legacy_status(username: username, wallet_balance: wallet_balance, shard: shard)
    end

    def self.status_by_ship_guid(ship_guid:, shard_uuid:, wallet_balance: nil)
      validate_wallet_balance!(wallet_balance)

      shard = Shard.find_by(channel_uuid: shard_uuid)
      raise ActiveRecord::RecordNotFound, 'Shard not found' unless shard

      user_ship = UserShip.find_by(guid: ship_guid)
      raise ActiveRecord::RecordNotFound, 'Ship not found' unless user_ship

      shard_user = user_ship.shard_user
      raise ActiveRecord::RecordNotFound, 'Shard user not found' unless shard_user
      raise ValidationError, 'Ship does not belong to this shard' unless shard_user.shard_id == shard.id

      status_response_for(shard_user: shard_user, user_ship: user_ship, wallet_balance: wallet_balance)
    end

    def self.legacy_status(username:, wallet_balance: nil, shard:)
      raise ValidationError, 'username is required for legacy status' if username.blank?
      raise ValidationError, 'shard is required for legacy status' if shard.blank?

      validate_wallet_balance!(wallet_balance)

      shard_record = Shard.find_by(channel_uuid: shard)
      raise ActiveRecord::RecordNotFound, 'Shard not found' unless shard_record

      user = find_or_create_user(username, shard_record)
      shard_user = user.shard_users.find_by(shard_id: shard_record.id)
      raise ActiveRecord::RecordNotFound, 'Shard user not found' unless shard_user

      status_response_for(
        shard_user: shard_user,
        user_ship: shard_user.user_ships.order(updated_at: :desc).first,
        wallet_balance: wallet_balance
      )




      

      

      
      # ✅ Check if user already has a ship
      
    
      # Gather Cargo Information
    end

    def self.status_response_for(shard_user:, user_ship:, wallet_balance:)
      update_status_wallet_balance!(shard_user, wallet_balance)

      return no_ship_status_response(shard_user) if user_ship.nil?

      cargo = user_ship_cargo_json(user_ship)
      ship_travel = ShipTravel.where(user_ship_id: user_ship.id).order(created_at: :desc).first
      current_tick = Tick.order(created_at: :desc).pluck(:current_tick).first

      {
        status: 'success',
        wallet_balance: shard_user.wallet_balance,
        ship: {
          model: user_ship.ship.model,
          location: user_ship.location_name,
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
        cargo: cargo,
      }
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


    def self.buy(username:, wallet_balance:, commodity_name:, scu:, shard:, ship_guid:, ship_slug:)

      
      user = User.where("LOWER(username) = ?", username.downcase).first!
      commodity = Commodity.where("name ILIKE ?", commodity_name).first!
      shard_user = user.shard_users.where("LOWER(shard_name) = ?", shard.downcase).first
      shard_user.update(wallet_balance:wallet_balance)
      shard = Shard.find_by_name(shard)
      user_ship = resolve_trade_ship(
        user: user,
        shard_user: shard_user,
        shard: shard,
        ship_guid: ship_guid,
        ship_slug: ship_slug,
        create_missing: true
      )
      

      if shard_user.wallet_balance == 0
        raise InsufficientCreditsError, "INSF FNDS '#{username}'."
      end
      
      candidate_facilities = buyable_facilities_for_trade_location(user_ship.location_name).to_a
      facility = candidate_facilities.find { |candidate| candidate.commodity_name.to_s.casecmp?(commodity.name) }
      location_name = facility&.location_name.presence || trade_facility_location_name(user_ship.location_name, candidate_facilities)

      if facility.nil?
        raise InsufficientInventoryError, "No matching facility found for #{location_name} and #{commodity.name}."
      elsif facility.inventory <= 0
        raise InsufficientInventoryError, "#{facility.location_name} Facility does not have enough inventory to sell."
      end

      if scu == "max"
        scu = ""
      end

      # ✅ Calculate the maximum affordable SCU based on wallet and cargo space
      buy_price = player_buy_price(facility)
      max_affordable_scu = (shard_user.wallet_balance / buy_price.to_f).floor
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
    
      # ✅ Validate Commodity Availability
      raise CommodityNotAvailableError, "Commodity not available at this location." unless facility.commodity.is_sellable
    

      # ✅ Perform Transaction
      ActiveRecord::Base.transaction do
        shard_user.update_credits(-total_cost)
    
        cargo = user_ship.user_ship_cargos.find_or_initialize_by(commodity_id: commodity.id)
        cargo.scu = cargo.scu.to_i + scu
        cargo.buy_price = buy_price
        cargo.commodity_name = commodity.name
        cargo.save!

# Find existing StarBitizenRun for the same commodity, ship, and buy location
star_bitizen_run = StarBitizenRun.find_by(
  user: user,
  user_ship: user_ship,
  commodity_name: commodity.name,
  buy_location_name: location_name,
  shard: shard,
  local_sell_price: nil
)

    if star_bitizen_run
      # ✅ Update existing StarBitizenRun record
      star_bitizen_run.update!(
        local_buy_price: buy_price, # Update to latest buy price
        scu: star_bitizen_run.scu + scu, # Add to existing SCU
        profit: 0 # Reset profit until sold
      )
    else
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
        shard: shard # Track game shard
      )
    end

        facility.update!(inventory: facility.inventory - scu)
      end

      user_ship_cargo = user_ship.user_ship_cargos.last

    
      # ✅ Return API Response
      {
        status: 'success',
        wallet_balance: shard_user.wallet_balance,
        loading_time: loading_time_seconds,
        loading_ticks: loading_ticks_for_scu(scu),
        scu: scu,
        capital: total_cost,
        message: "Purchased #{scu} SCU of #{commodity_name} at #{location_name}"
      }
    end    

   # I need to build something that can split a starbitizenrun if they decided to split their cargo.

    def self.sell(username:, wallet_balance:, commodity_name: nil, scu: nil, shard:)
      user = User.where("LOWER(username) = ?", username.downcase).first!
      shard_user = user.shard_users.where("LOWER(shard_name) = ?", shard.downcase).first
    
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
          shard: shard
        )

                # Update trade record
                if star_bitizen_run.present?
                  star_bitizen_run.update!(
                    local_sell_price: sell_price,
                    sell_location_name: location.name,
                    profit: total_revenue,
                    scu: scu_to_sell
                  )
                end

        cargo_to_sell.scu <= 0 ? cargo_to_sell.destroy! : cargo_to_sell.save!

        facility.update!(inventory: [facility.inventory + scu_to_sell, facility.max_inventory].min)
      end
    
      # ✅ Return API Response
      {
        status: 'success',
        profit: total_revenue,
        capital: total_revenue,
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
      

      def self.list_available_commodities(username:, shard:, ship_guid: nil, ship_slug: nil)
        user = User.where("LOWER(username) = ?", username.downcase).first!
        shard_user = user.shard_users.where("LOWER(shard_name) = ?", shard.downcase).first
        raise ShipNotFoundError, "No ship found for user '#{username}'." if shard_user.nil?

        user_ship = resolve_trade_ship(
          user: user,
          shard_user: shard_user,
          shard: Shard.find_by_name(shard),
          ship_guid: ship_guid,
          ship_slug: ship_slug,
          create_missing: false
        )
        raise ShipNotFoundError, "No ship found for user '#{username}'." if user_ship.nil?

        location_name = user_ship.location_name
        commodities = buyable_facilities_for_trade_location(location_name).includes(:commodity).to_a
        response_location_name = trade_facility_location_name(location_name, commodities)

        commodities = commodities.map do |facility|
          {
            commodity_name: facility.commodity.name,
            price: player_buy_price(facility)
          }
        end

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
        (scu.to_d * unit_price.to_d).round(2).to_f
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
  
