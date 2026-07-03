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
    facility.player_buy_price
  end

  def player_sell_price_for(facility)
    facility.player_sell_price
  end

  def player_can_buy_from?(facility)
    facility.player_can_buy?
  end

  def player_can_sell_to?(facility)
    facility.player_can_sell?
  end

  def market_spread(facility)
    player_sell_price_for(facility) - player_buy_price_for(facility)
  end
end
