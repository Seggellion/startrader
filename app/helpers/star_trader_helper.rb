module StarTraderHelper
  def market_price(value)
    number_to_currency(value.to_d, unit: "aUEC ", precision: 2)
  end

  def market_quantity(value)
    number_with_delimiter(value.to_i)
  end

  def market_location_context(location)
    return "Uncharted" unless location

    [
      location.star_system_name,
      location.planet_name,
      location.moon_name,
      location.parent_name
    ].compact_blank.uniq.join(" / ").presence || location.classification.to_s.titleize
  end

  def player_buy_price_for(facility)
    active_market_price(facility.local_sell_price, facility.price_sell)
  end

  def player_sell_price_for(facility)
    active_market_price(facility.local_buy_price, facility.price_buy)
  end

  def terminal_sells_to_player?(facility)
    player_buy_price_for(facility).positive?
  end

  def terminal_buys_from_player?(facility)
    player_sell_price_for(facility).positive?
  end

  def market_spread(facility)
    player_sell_price_for(facility) - player_buy_price_for(facility)
  end

  private

  def active_market_price(local_price, imported_price)
    local_value = local_price.present? ? local_price.to_d : 0.to_d
    imported_value = imported_price.present? ? imported_price.to_d : 0.to_d

    local_value.positive? ? local_value : imported_value
  end
end
