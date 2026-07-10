# app/models/production_facility.rb

class ProductionFacility < ApplicationRecord
  include ActionView::RecordIdentifier

  PLAYER_BUY_PRICE_SQL = "COALESCE(NULLIF(production_facilities.local_buy_price, 0), production_facilities.price_buy, 0)"
  PLAYER_SELL_PRICE_SQL = "COALESCE(NULLIF(production_facilities.local_sell_price, 0), production_facilities.price_sell, 0)"
  PLAYER_CAN_BUY_SQL = [
    "COALESCE(production_facilities.local_buy_price, 0) > 0",
    "COALESCE(production_facilities.price_buy, 0) > 0",
    "COALESCE(production_facilities.scu_buy, 0) > 0",
    "COALESCE(production_facilities.status_buy, 0) > 0",
    "COALESCE(production_facilities.production_rate, 0) > 0"
  ].join(" OR ")
  PLAYER_CAN_SELL_SQL = [
    "COALESCE(production_facilities.local_sell_price, 0) > 0",
    "COALESCE(production_facilities.price_sell, 0) > 0",
    "COALESCE(production_facilities.scu_sell, 0) > 0",
    "COALESCE(production_facilities.scu_sell_stock, 0) > 0",
    "COALESCE(production_facilities.status_sell, 0) > 0",
    "COALESCE(production_facilities.consumption_rate, 0) > 0"
  ].join(" OR ")

  belongs_to :location, primary_key: :name, foreign_key: :location_name, optional: true

  # Using `commodity_name` instead of `commodity_id`
  belongs_to :commodity,
             primary_key: :name,
             foreign_key: :commodity_name,
             optional: true

  validates :facility_name, :production_rate, :consumption_rate, presence: true

  thread_mattr_accessor :suppress_market_broadcasts, default: false

  after_update_commit :broadcast_market_row, if: :should_broadcast_market_row?

  scope :with_commodity_name, -> { where("NULLIF(TRIM(COALESCE(commodity_name, '')), '') IS NOT NULL") }
  scope :with_terminal_context, -> {
    where(
      "NULLIF(TRIM(COALESCE(location_name, '')), '') IS NOT NULL OR " \
        "NULLIF(TRIM(COALESCE(terminal_name, '')), '') IS NOT NULL OR " \
        "id_terminal IS NOT NULL"
    )
  }
  scope :likely_trade_available, -> {
    where(
      "COALESCE(local_buy_price, 0) > 0 OR COALESCE(price_buy, 0) > 0 OR " \
        "COALESCE(local_sell_price, 0) > 0 OR COALESCE(price_sell, 0) > 0 OR " \
        "COALESCE(status_buy, 0) > 0 OR COALESCE(status_sell, 0) > 0 OR " \
        "COALESCE(scu_buy, 0) > 0 OR COALESCE(scu_sell, 0) > 0 OR " \
        "COALESCE(scu_sell_stock, 0) > 0 OR COALESCE(production_rate, 0) > 0 OR " \
        "COALESCE(consumption_rate, 0) > 0 OR COALESCE(inventory, 0) > 0"
    )
  }
  scope :trade_available, -> { with_commodity_name.with_terminal_context.likely_trade_available }
  scope :ordered_for_api, -> { order(:location_name, :terminal_name, :commodity_name, :id) }
  scope :player_can_buy, -> { where("(#{PLAYER_CAN_BUY_SQL})") }
  scope :player_can_sell, -> { where("(#{PLAYER_CAN_SELL_SQL})") }

  def commodity_api_id
    api_id.presence || id
  end

  def commodity_display_name
    commodity_name.presence || commodity&.name
  end

  def terminal_display_name(terminal: nil, location: nil)
    display_location_name = location_name.presence || terminal&.location_name.presence || location&.name
    display_terminal_name = terminal_name.presence || terminal&.name.presence || terminal&.nickname.presence

    if display_location_name.present? && display_terminal_name.present?
      return display_location_name if display_location_name == display_terminal_name

    #  "#{display_location_name} - #{display_terminal_name}"
    "#{display_location_name}"
    else
      display_location_name.presence || display_terminal_name.presence
    end
  end

  def api_buy_price
    active_price(local_buy_price, price_buy)
  end

  def api_sell_price
    active_price(local_sell_price, price_sell)
  end

  def player_can_buy?
    decimal_value(local_buy_price).positive? ||
      decimal_value(price_buy).positive? ||
      scu_buy.to_i.positive? ||
      status_buy.to_i.positive? ||
      decimal_value(production_rate).positive?
  end

  def player_can_sell?
    decimal_value(local_sell_price).positive? ||
      decimal_value(price_sell).positive? ||
      scu_sell.to_i.positive? ||
      scu_sell_stock.to_i.positive? ||
      status_sell.to_i.positive? ||
      decimal_value(consumption_rate).positive?
  end

  def player_buy_price
    active_decimal_price(local_buy_price, price_buy)
  end

  def player_sell_price
    active_decimal_price(local_sell_price, price_sell)
  end

  def purchasable?
    api_buy_price.positive?
  end

  def sellable?
    api_sell_price.positive? &&
      (
        status_sell.to_i.positive? ||
        scu_sell_stock.to_i.positive? ||
        scu_sell.to_i.positive? ||
        production_rate.to_i.positive? ||
        inventory.to_i.positive?
      )
  end

  def trade_available?
    commodity_display_name.present? && (purchasable? || sellable?) && (api_buy_price.positive? || api_sell_price.positive?)
  end

  def vice?
    commodity&.is_illegal? || false
  end

  def out_of_date?
    updated_at < 30.days.ago
  end

  def api_sort_key(terminal: nil, location: nil)
    [
      location&.star_system_name.to_s,
      location&.planet_name.to_s,
      location&.moon_name.to_s,
      location_name.presence || terminal&.location_name.to_s,
      terminal_name.presence || terminal&.name.to_s,
      commodity_display_name.to_s,
      id
    ]
  end

  # Generate resources on game ticks
  def produce    
    self.inventory = [inventory + production_rate, max_inventory].min
    save!
  end

  # Consume resources during gameplay (e.g., population or ship requirements)
  def consume
    self.inventory = [inventory - consumption_rate, 0].max
    save!
  end

  def broadcast_market_row
    broadcast_replace_later_to(
      "market_prices",
      target: dom_id(self, :market_row),
      partial: "star_trader/market_row",
      locals: { facility: self }
    )
  end

  def self.without_market_broadcasts
    previous = suppress_market_broadcasts
    self.suppress_market_broadcasts = true
    yield
  ensure
    self.suppress_market_broadcasts = previous
  end

  private

  def active_price(local_price, imported_price)
    preferred_price = local_price.present? ? local_price.to_d : 0.to_d
    fallback_price = imported_price.present? ? imported_price.to_d : 0.to_d

    (preferred_price.positive? ? preferred_price : fallback_price).to_i
  end

  def active_decimal_price(local_price, imported_price)
    preferred_price = decimal_value(local_price)
    fallback_price = decimal_value(imported_price)

    preferred_price.positive? ? preferred_price : fallback_price
  end

  def decimal_value(value)
    value.present? ? value.to_d : 0.to_d
  end

  def should_broadcast_market_row?
    !self.class.suppress_market_broadcasts && market_values_changed?
  end

  def market_values_changed?
    (previous_changes.keys & %w[
      inventory
      max_inventory
      local_buy_price
      local_sell_price
      price_buy
      price_sell
      scu_buy
      scu_sell
      scu_sell_stock
      status_buy
      status_sell
      production_rate
      consumption_rate
      commodity_name
      terminal_name
      location_name
    ]).any?
  end
end
