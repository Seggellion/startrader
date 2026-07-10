class MarketPriceUpdater
  # ==========================================
  # 🎛️ MARKET VOLATILITY LEVERS
  # ==========================================
  
  # How far prices can swing above or below the base price.
  #originally this was 1.25  and 0.75
  # 1.15 = 15% above base, 0.85 = 15% below base.
  MAX_PRICE_MODIFIER = 1.15
  MIN_PRICE_MODIFIER = 0.85

  # How quickly the price moves toward its new target per tick.
  # Originally this was 0.25
  # 0.10 means it moves 10% of the way there. Lower = slower, smoother changes.
  SMOOTHING_SPEED = 0.10
  
  # Minimum percentage change required to trigger a database update.
  # 0.02 = 2%. Prevents micro-fluctuations from spamming the database.
  MIN_UPDATE_THRESHOLD = 0.02

  # ==========================================

  def self.update_prices!(broadcast: false)
    Rails.logger.info "MarketPriceUpdater: Starting batch price update for ProductionFacilities."

    ProductionFacility.find_in_batches(batch_size: 500) do |facilities|
      facilities_data = facilities.map do |facility|
        calculate_new_prices(facility)
      end.compact

      update_facilities_in_bulk(facilities_data, broadcast: broadcast) if facilities_data.any?
    end

    Rails.logger.info "MarketPriceUpdater: Completed batch price update."
  end

  private

  def self.calculate_new_prices(facility)
    return if facility.max_inventory.zero?

    inventory_ratio = facility.inventory.to_f / facility.max_inventory
    
    # Pre-calculate the scaling factor (1.0 = empty inventory, 0.0 = full inventory)
    demand_multiplier = 1.0 - inventory_ratio 
    
    # Calculate exactly where the price should sit between MIN and MAX based on demand
    price_range = MAX_PRICE_MODIFIER - MIN_PRICE_MODIFIER
    target_modifier = MIN_PRICE_MODIFIER + (demand_multiplier * price_range)

    supports_buying = facility.price_buy > 0
    supports_selling = facility.price_sell > 0

    price_updates = {}

    if supports_buying
      base_buy_price = facility.price_buy.to_d
      target_buy_price = base_buy_price * target_modifier

      # Blend old price with target price based on SMOOTHING_SPEED
      current_buy_price = facility.local_buy_price.to_d
      smoothed_buy_price = current_buy_price + ((target_buy_price - current_buy_price) * SMOOTHING_SPEED)

      if price_changed_enough?(current_buy_price, smoothed_buy_price)
        price_updates[:local_buy_price] = smoothed_buy_price
      end
    end

    if supports_selling
      base_sell_price = facility.price_sell.to_d
      target_sell_price = base_sell_price * target_modifier

      # Blend old price with target price based on SMOOTHING_SPEED
      current_sell_price = facility.local_sell_price.to_d
      smoothed_sell_price = current_sell_price + ((target_sell_price - current_sell_price) * SMOOTHING_SPEED)

      if price_changed_enough?(current_sell_price, smoothed_sell_price)
        price_updates[:local_sell_price] = smoothed_sell_price
      end
    end

    price_updates[:id] = facility.id if price_updates.any?
    price_updates.presence
  rescue => e
    Rails.logger.error "Failed to calculate new price for facility #{facility.id}: #{e.message}"
    nil
  end

  # Helper method to check if the change exceeds our threshold
  def self.price_changed_enough?(old_price, new_price)
    return true if old_price.zero? # Always update if the old price was completely zeroed out
    
    percent_change = (new_price - old_price).abs / old_price
    percent_change > MIN_UPDATE_THRESHOLD
  end

  def self.update_facilities_in_bulk(facilities_data, broadcast: false)
    return if facilities_data.empty?

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

    if update_statements.any?
      sql = <<-SQL.squish
        UPDATE production_facilities
        SET #{update_statements.join(', ')}
        WHERE id IN (#{ids.join(', ')})
      SQL

      ActiveRecord::Base.connection.execute(sql)
      
      if broadcast && !ProductionFacility.suppress_market_broadcasts
        ProductionFacility.where(id: ids).find_each(&:broadcast_market_row)
      end

      Rails.logger.info "MarketPriceUpdater: Bulk updated #{ids.size} facilities with price changes."
    end
  end
end