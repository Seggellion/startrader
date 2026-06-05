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

  def market_spread(facility)
    facility.local_buy_price.to_d - facility.local_sell_price.to_d
  end
end
