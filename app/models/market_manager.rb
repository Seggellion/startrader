class MarketManager
    def self.adjust_prices(city)
      city.city_commodities.each do |commodity|
        supply = commodity.quantity > 0 ? commodity.quantity : commodity.weight
        base_price = commodity.base_price || 0.0
  
        new_price = if supply >= commodity.max_supply_cap
                      0.0
                    elsif supply <= 0
                      base_price * 1.05
                    else
                      base_price * 1.05 * (1.0 - (supply / commodity.max_supply_cap))
                    end
  
        commodity.update!(current_price: new_price)
      end
    end
  end
  