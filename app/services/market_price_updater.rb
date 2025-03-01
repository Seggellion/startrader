# app/services/market_price_updater.rb


class MarketPriceUpdater
    # Called on each tick to update market prices dynamically
    def self.update_prices!
      Rails.logger.info "MarketPriceUpdater: Starting batch price update for ProductionFacilities."
  
      # Batch process facilities to avoid memory overflow and optimize performance
      ProductionFacility.find_in_batches(batch_size: 500) do |facilities|
        facilities_data = facilities.map do |facility|
          calculate_new_prices(facility)
        end.compact
  
        # Bulk update facilities with new pricing only if prices have changed
        update_facilities_in_bulk(facilities_data) if facilities_data.any?
      end
  
      Rails.logger.info "MarketPriceUpdater: Completed batch price update."
    end
  
    private
  
    # Calculate new prices based on inventory levels and location classifications
    def self.calculate_new_prices(facility)
      return if facility.max_inventory.zero?
  
      inventory_ratio = BigDecimal(facility.inventory.to_f / facility.max_inventory, 5)
      base_price = facility.commodity.price_sell.to_d
  
      # Set price limits based on classification
      max_price = BigDecimal(base_price * 1.5, 10)
      min_price = BigDecimal(base_price * 0.5, 10)
  
      # Calculate the price multiplier based on inventory levels
      price_multiplier = BigDecimal('1.0') + (BigDecimal('0.5') - inventory_ratio)
      new_price = BigDecimal(base_price * price_multiplier, 10)
  
      # Ensure the new price is within valid bounds
      new_price = [min_price, new_price, max_price].sort[1]
      new_buy_price = (new_price * BigDecimal('0.9'))
  
      # Only return data if the price has changed
      if new_price != facility.local_sell_price.to_d || new_buy_price != facility.local_buy_price.to_d
        {
          id: facility.id,
          local_sell_price: new_price,
          local_buy_price: new_buy_price
        }
      end
    rescue => e
      Rails.logger.error "Failed to calculate new price for facility #{facility.id}: #{e.message}"
      nil
    end
  
    # Bulk update production facilities using ActiveRecord's update_all
    def self.update_facilities_in_bulk(facilities_data)
      return if facilities_data.empty?
  
      # Build SQL fragments for bulk update
      sell_price_cases = []
      buy_price_cases = []
      ids = []
  
      facilities_data.each do |data|
        ids << data[:id]
        sell_price_cases << "WHEN #{data[:id]} THEN #{data[:local_sell_price].to_f}"
        buy_price_cases << "WHEN #{data[:id]} THEN #{data[:local_buy_price].to_f}"
      end
  
      # Execute bulk update in a single query
      sql = <<-SQL.squish
        UPDATE production_facilities
        SET local_sell_price = CASE id #{sell_price_cases.join(' ')} END,
            local_buy_price = CASE id #{buy_price_cases.join(' ')} END
        WHERE id IN (#{ids.join(', ')})
      SQL
  
      ActiveRecord::Base.connection.execute(sql)
      Rails.logger.info "MarketPriceUpdater: Bulk updated #{ids.size} facilities with price changes."
    end
  end