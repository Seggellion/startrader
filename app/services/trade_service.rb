
  # app/services/trade_service.rb

class TradeService
    class InsufficientCreditsError < StandardError; end
    class InsufficientCapacityError < StandardError; end
    class CommodityNotAvailableError < StandardError; end
    class LocationMismatchError < StandardError; end
    class InsufficientInventoryError < StandardError; end
    class UserNotFoundError < StandardError; end
    class ShipNotFoundError < StandardError; end
  
    def self.status(username:, wallet_balance: nil, shard:)
      user = find_or_create_user(username, shard)
      shard_user = user.shard_users.find_by(shard_name:shard)

      if wallet_balance.present?
        shard_user.update!(wallet_balance: wallet_balance)
      end  

      if shard_user.wallet_balance == 0
        shard_user.update!(wallet_balance: 15000)
      end

      # ✅ Check if user already has a ship
      user_ship = user.user_ships.first
    
      if user_ship.nil?
        # ✅ If no ship exists, give them a Caterpillar ship
        caterpillar_ship = Ship.find_by(slug: 'caterpillar')  # Ensure this ship model exists
    
        if caterpillar_ship.nil?
          raise ShipNotFoundError, "The Caterpillar ship is missing from the database."
        end
    
        user_ship = UserShip.create!(
          user: user,
          ship: caterpillar_ship,
          location_name: 'Lorville', # Default starting location
          total_scu: 576,  # Caterpillar has 576 SCU
          used_scu: 0,
          shard_name: shard 
        )
    
        Rails.logger.info "Caterpillar ship granted to user: #{username}"
      end
    
      # Gather Cargo Information
      cargo = user_ship.user_ship_cargos.includes(:commodity).map do |cargo_item|
        {
          commodity_name: cargo_item.commodity.name,
          scu: cargo_item.scu
        }
      end
    
      # Retrieve Ship Travel Information
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
          travel_status: ship_travel ? 'In Transit' : 'Stationary',
          from_location: ship_travel&.from_location&.name,
          to_location: ship_travel&.to_location&.name,
          arrival_tick: ship_travel&.arrival_tick,
          current_tick: current_tick,
          time_remaining: ship_travel ? [ship_travel.arrival_tick - current_tick, 0].max : nil
        },
        cargo: cargo,
      }
    end
    

    def self.buy(username:, wallet_balance:, commodity_name:, scu:, shard:)
      
      user = User.where("LOWER(username) = ?", username.downcase).first!
      commodity = Commodity.find_by!(name: commodity_name)
      
      shard_user = ShardUser.find_or_create_by(user_id: user.id, shard_name: shard)
      # ✅ Get the user's most recent UserShip to determine location
      user_ship = shard_user.user_ships.order(updated_at: :desc).first
      
      if user_ship.nil?
        raise ShipNotFoundError, "No ship found for user '#{username}'."
      end
      

      if shard_user.wallet_balance == 0
        raise InsufficientCreditsError, "INSF FNDS '#{username}'."
      end

      location_name = user_ship.location_name
      location = Location.find_by!(name: location_name)
    
      facility = ProductionFacility.find_by!(location_name: location.name, commodity_id: commodity.id)
      raise InsufficientInventoryError, "#{facility.location_name} Facility does not have enough inventory to sell." if facility.nil? || facility.inventory <= 0
          

      # ✅ Calculate the maximum affordable SCU based on wallet and cargo space
      max_affordable_scu = (shard_user.wallet_balance / facility.local_buy_price.to_f).floor
      max_cargo_space = user_ship.available_cargo_space
      max_facility_inventory = facility.inventory
    
      # ✅ Default SCU to the maximum possible if not provided or if too large
      scu = [scu.to_i, max_affordable_scu, max_cargo_space, max_facility_inventory].select { |v| v > 0 }.min
      raise InsufficientInventoryError, "Not enough cargo inventory at facility. Available: #{facility.inventory} SCU." if scu > facility.inventory
    
      total_cost = facility.local_buy_price.to_f * scu
      loading_time = (scu * 2) + 10  # Example calculation
    
      # ✅ Validate Commodity Availability
      raise CommodityNotAvailableError, "Commodity not available at this location." unless facility.commodity.is_sellable
    

      # ✅ Perform Transaction
      ActiveRecord::Base.transaction do
        shard_user.update_credits(-total_cost)
    
        cargo = user_ship.user_ship_cargos.find_or_initialize_by(commodity_id: commodity.id)
        cargo.scu = cargo.scu.to_i + scu
        cargo.buy_price = facility.local_buy_price
        cargo.commodity_name = commodity.name
        cargo.save!
    
        user_ship.add_cargo_scu(scu)

        # Create StarBitizenRun record
        star_bitizen_run = StarBitizenRun.create!(
          user: user,
          commodity: commodity,
          commodity_name: commodity.name,
          local_buy_price: facility.local_buy_price,
          local_sell_price: nil, # Will be updated later
          scu: scu,
          buy_location_name: location.name,
          sell_location_name: nil, # Will be updated later
          profit: 0,
          user_ship_cargo_id: user_ship.user_ship_cargos.last.id,
          user_ship_id: user_ship.id,
          shard: shard # Track game shard
        )

        facility.update!(inventory: facility.inventory - scu)
      end

      user_ship_cargo = user_ship.user_ship_cargos.last

    
      # ✅ Return API Response
      {
        status: 'success',
        wallet_balance: shard_user.wallet_balance,
        loading_time: loading_time,
        capital: total_cost,
        message: "Purchased #{scu} SCU of #{commodity_name} at #{location_name}. Loading will complete in #{loading_time / 60} minutes."
      }
    end    

    def self.sell(username:, wallet_balance:, commodity_name: nil, scu: nil, shard:)
      user = User.where("LOWER(username) = ?", username.downcase).first!
      shard_user = ShardUser.find_or_create_by(user_id: user.id, shard_name: shard)
      user_ship = shard_user.user_ships.order(updated_at: :desc).first
      raise ShipNotFoundError, "No ship found for user '#{username}'." unless user_ship
    
      shard_user.update!(wallet_balance: wallet_balance)
    
      location_name = user_ship.location_name
      location = Location.find_by!(name: location_name)
    
      # ✅ If no commodity is specified, get all buyable commodities at this location
      if commodity_name.blank?
        buyable_commodities = ProductionFacility.where(location_name: location.name)
                                                .where("local_sell_price > 0")
                                                .pluck(:commodity_name) # ✅ Match by name
      else
        buyable_commodities = [commodity_name] # ✅ Directly match the given commodity name
      end

    
      # ✅ Get all cargo that matches the buyable commodities
      cargo_to_sell = user_ship.user_ship_cargos.includes(:commodity).where(commodities: { name: buyable_commodities }) # ✅ Match by name
    
      if cargo_to_sell.empty?
        raise InsufficientInventoryError, "No matching cargo to sell at #{location_name}."
      end
      total_profit = 0
      transactions = []
    
      ActiveRecord::Base.transaction do
        cargo_to_sell.each do |cargo|
          facility = ProductionFacility.find_by(location_name: location.name, commodity_name: cargo.commodity.name) # ✅ Match by name          
    
          next if facility.nil? || facility.inventory >= facility.max_inventory  # Skip if facility can't buy more
    
          max_scu = cargo.scu if scu.blank? || scu.to_i <= 0
          max_facility_demand = facility.inventory
          scu_to_sell = [max_scu, max_facility_demand].select { |v| v > 0 }.min
    
          if cargo.scu < scu_to_sell
            raise InsufficientInventoryError, "Not enough inventory to sell. You have #{cargo.scu} SCU of #{cargo.commodity.name}."
          end
    
          # ✅ Calculate Profit
          total_revenue = facility.local_sell_price.to_f * scu_to_sell
          total_profit += total_revenue
    
          # ✅ Perform Transaction
          shard_user.update_credits(total_revenue)
          
          # ✅ Update Cargo
          cargo.scu -= scu_to_sell
          star_bitizen_run = StarBitizenRun.find_by(user_ship_cargo_id: cargo.id)
          star_bitizen_run.update(user_ship_cargo_id: nil)
          cargo.scu <= 0 ? cargo.destroy! : cargo.save!
          
    
          # ✅ Update Ship Cargo Capacity
          user_ship.remove_cargo_scu(scu_to_sell)
    
          # ✅ Update Facility Inventory
          facility.update!(inventory: [facility.inventory + scu_to_sell, facility.max_inventory].min)
    
          star_bitizen_run = StarBitizenRun.find_by(
            user: user,
            user_ship: user_ship,
            commodity_name: cargo.commodity.name,
            local_sell_price: nil,
            shard: shard
          )

                  # Update trade record
        star_bitizen_run.update!(
          local_sell_price: facility.local_sell_price,
          sell_location_name: location.name,
          profit: total_profit,
          scu: scu_to_sell
        )

          transactions << {
            commodity_name: cargo.commodity.name,
            scu_sold: scu_to_sell,
            total_price: total_revenue
          }
        end
      end



    
      # ✅ Return API Response
      {
        status: 'success',
        profit: total_profit,
        wallet_balance: shard_user.wallet_balance,
        transactions: transactions
      }
    end
    


       
    def self.find_or_create_user(username, shard)
        normalized_username = username.downcase.strip
        
        # ✅ Find user case-insensitively
        user = User.where("LOWER(username) = ?", normalized_username).first
        
        shard = Shard.find_by_name(shard)
        
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
        

        


        unless user.shard_users&.find_by(shard_name: shard.name)
          
          ShardUser.create(user_id: user.id, shard_id: shard.id, shard_name: shard.name)
        end

        user
      end
      

      def self.list_available_commodities(username:)
        user = User.where("LOWER(username) = ?", username.downcase).first!
        user_ship = user.user_ships.order(updated_at: :desc).first
      
        if user_ship.nil?
          raise ShipNotFoundError, "No ship found for user '#{username}'."
        end
      
        location_name = user_ship.location_name
        location = Location.find_by!(name: location_name)
      
        commodities = ProductionFacility.where(location_name: location.name)
                                         .where("local_buy_price > 0")  # ✅ Only show buyable commodities
                                         .includes(:commodity)
                                         .map do |facility|
          {
            commodity_name: facility.commodity.name,
            price: facility.local_buy_price
          }
        end
      
        if commodities.empty?
          return { status: 'error', message: "No commodities available for purchase at #{location_name}." }
        end
      
        {
          status: 'success',
          location: location_name,
          commodities: commodities
        }
      end
      


  end
  