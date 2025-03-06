
  # app/services/trade_service.rb

class TradeService
    class InsufficientCreditsError < StandardError; end
    class InsufficientCapacityError < StandardError; end
    class CommodityNotAvailableError < StandardError; end
    class LocationMismatchError < StandardError; end
    class InsufficientInventoryError < StandardError; end
    class UserNotFoundError < StandardError; end
    class ShipNotFoundError < StandardError; end
  
    def self.status(username:, wallet_balance: nil)
      user = User.where("LOWER(username) = ?", username.downcase).first!
    
      if wallet_balance.present?
        user.update!(wallet_balance: wallet_balance)
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
          used_scu: 0
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
        wallet_balance: user.wallet_balance,
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
    

    def self.buy(username:, wallet_balance:, commodity_name:, scu:)
      user = User.find_by!(username: username)
      commodity = Commodity.find_by!(name: commodity_name)
    
      # ✅ Get the user's most recent UserShip to determine location
      user_ship = user.user_ships.order(updated_at: :desc).first
    
      if user_ship.nil?
        raise ShipNotFoundError, "No ship found for user '#{username}'."
      end
  
      location_name = user_ship.location_name
      location = Location.find_by!(name: location_name)
    
      facility = ProductionFacility.find_by!(location_name: location.name, commodity_id: commodity.id)
      raise InsufficientInventoryError, "#{facility.location_name} Facility does not have enough inventory to sell." if facility.nil? || facility.inventory <= 0
    

      puts user.username
      puts commodity.name
      puts user_ship.ship.slug
      puts location.name
      puts facility.facility_name

      # ✅ Calculate the maximum affordable SCU based on wallet and cargo space
      max_affordable_scu = (wallet_balance / facility.local_buy_price.to_f).floor
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
        user.update_credits(-total_cost)
    
        cargo = user_ship.user_ship_cargos.find_or_initialize_by(commodity_id: commodity.id)
        cargo.scu = cargo.scu.to_i + scu
        cargo.save!
    
        user_ship.add_cargo_scu(scu)
        facility.update!(inventory: facility.inventory - scu)
      end
    
      # ✅ Return API Response
      {
        status: 'success',
        wallet_balance: user.wallet_balance,
        loading_time: loading_time,
        capital: total_cost,
        message: "Purchased #{scu} SCU of #{commodity_name} at #{location_name}. Loading will complete in #{loading_time / 60} minutes."
      }
    end    

    def self.sell(username:, wallet_balance:, commodity_name:, scu:)
        user = User.find_by!(username: username)
        user.update(wallet_balance: wallet_balance)
        commodity = Commodity.find_by!(name: commodity_name)
        location_name = user_ship.location_name
        location = Location.find_by!(name: location_name)
        facility = ProductionFacility.find_by!(location_name: location.name, commodity_id: commodity.id)
    
        user_ship = user.user_ships.first

        
        if facility.inventory >= facility.max_inventory
          raise InsufficientCapacityError, "Facility has reached max inventory and cannot buy more."
        end

        # Validate Location Match
        if user_ship.location_name != facility.location_name
          raise LocationMismatchError, "Your ship is currently at '#{user_ship.location_name}', but the commodity can be sold at '#{facility.location_name}'. You need to travel to the correct location first."
        end
    
        # Validate Commodity Availability for Selling
        unless facility.commodity.is_buyable
          raise CommodityNotAvailableError, "Commodity cannot be sold at this location."
        end
    
        # Validate Cargo Availability
        cargo = user_ship.user_ship_cargos.find_by(commodity_id: commodity.id)
        if cargo.nil? || cargo.scu <= 0
          raise InsufficientInventoryError, "Not enough inventory to sell. You have #{cargo&.scu || 0} SCU of #{commodity_name}."
        end
    
        # Default to selling all available cargo if `scu` is blank or <= 0
        scu = cargo.scu if scu.blank? || scu.to_i <= 0
    
        max_facility_demand = facility.inventory
        scu = [scu.to_i, max_facility_demand].select { |v| v > 0 }.min

        # Validate SCU amount
        if cargo.scu < scu
          raise InsufficientInventoryError, "Not enough inventory to sell. You have #{cargo.scu} SCU of #{commodity_name}."
        end
    
        # Calculate Profit
        total_revenue = facility.price_sell.to_f * scu
        loading_time = (scu * 2) + 10 # Example calculation
    
        # Perform Transaction
        ActiveRecord::Base.transaction do
          user.update_credits(total_revenue)
    
          # Update Cargo
          cargo.scu -= scu
          if cargo.scu <= 0
            cargo.destroy!
          else
            cargo.save!
          end
    
          # Update Ship Cargo Capacity
          user_ship.remove_cargo_scu(scu)
          
          facility.update!(inventory: [facility.inventory + scu, facility.max_inventory].min)
        end
    
        # Return API Response
        {
          status: 'success',
          profit: total_revenue,
          wallet_balance: user.wallet_balance,
          loading_time: loading_time,
          message: "Sold #{scu} SCU of #{commodity_name}. Funds have been credited to your account."
        }
      end


  end
  