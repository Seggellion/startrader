
class MarketPriceUpdater
  # Called on each tick to update market prices dynamically
  def self.update_prices!
    Rails.logger.info "MarketPriceUpdater: Starting batch price update for ProductionFacilities."

    # Batch process facilities to optimize performance
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

  # Calculate new prices based on inventory levels
# Calculate new prices with reduced volatility
def self.calculate_new_prices(facility)
  return if facility.max_inventory.zero?

  inventory_ratio = facility.inventory.to_f / facility.max_inventory

  # Ensure that if inventory is 0, we set max demand (i.e., highest price)
  adjusted_inventory_ratio = inventory_ratio.zero? ? 0.0 : inventory_ratio # 0 means max price, 1 means min price

  supports_buying = facility.price_buy > 0
  supports_selling = facility.price_sell > 0

  price_updates = {}

  # 🔵 Adjust **Buy Price** only if the facility supports buying
  if supports_buying
    base_buy_price = facility.price_buy.to_d
    max_buy_price = BigDecimal(base_buy_price * 1.25, 10) # Less aggressive cap
    min_buy_price = BigDecimal(base_buy_price * 0.75, 10) # Less aggressive floor

    # Less aggressive scaling factor (reducing 1.5 to 1.25)
    new_buy_price = base_buy_price * (1.25 - adjusted_inventory_ratio) # Closer to 1.25x when inventory is low
    new_buy_price = [min_buy_price, new_buy_price, max_buy_price].sort[1] # Clamp within limits

    # 🔄 Apply smoothing: blend with current price (75% old price, 25% new)
    smoothed_buy_price = facility.local_buy_price.to_d * 0.75 + new_buy_price * 0.25

    # Ignore small fluctuations (less than ±2%)
    if (smoothed_buy_price - facility.local_buy_price.to_d).abs / facility.local_buy_price.to_d > 0.02
      price_updates[:local_buy_price] = smoothed_buy_price
    end
  end

  # 🔴 Adjust **Sell Price** only if the facility supports selling
  if supports_selling
    base_sell_price = facility.price_sell.to_d
    max_sell_price = BigDecimal(base_sell_price * 1.25, 10) # Less aggressive cap
    min_sell_price = BigDecimal(base_sell_price * 0.75, 10) # Less aggressive floor

    # 🔥 Less aggressive sell price scaling factor
    new_sell_price = base_sell_price * (0.75 + (1.0 - adjusted_inventory_ratio) * 0.5) 
    new_sell_price = [min_sell_price, new_sell_price, max_sell_price].sort[1] # Clamp within limits

    # 🔄 Apply smoothing: blend with current price (75% old price, 25% new)
    smoothed_sell_price = facility.local_sell_price.to_d * 0.75 + new_sell_price * 0.25

    # Ignore small fluctuations (less than ±2%)
    if (smoothed_sell_price - facility.local_sell_price.to_d).abs / facility.local_sell_price.to_d > 0.02
      price_updates[:local_sell_price] = smoothed_sell_price
    end
  end

  # Return only if there are actual price changes
  price_updates[:id] = facility.id if price_updates.any?
  price_updates.presence
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
      sell_price_cases << "WHEN #{data[:id]} THEN #{data[:local_sell_price].to_f}" if data[:local_sell_price]
      buy_price_cases << "WHEN #{data[:id]} THEN #{data[:local_buy_price].to_f}" if data[:local_buy_price]
    end

    update_statements = []
    update_statements << "local_sell_price = CASE id #{sell_price_cases.join(' ')} END" if sell_price_cases.any?
    update_statements << "local_buy_price = CASE id #{buy_price_cases.join(' ')} END" if buy_price_cases.any?

    # Execute bulk update in a single query if there are price changes
    if update_statements.any?
      sql = <<-SQL.squish
        UPDATE production_facilities
        SET #{update_statements.join(', ')}
        WHERE id IN (#{ids.join(', ')})
      SQL

      ActiveRecord::Base.connection.execute(sql)
      Rails.logger.info "MarketPriceUpdater: Bulk updated #{ids.size} facilities with price changes."
    end
  end
end