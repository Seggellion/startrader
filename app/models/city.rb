
  class City < ApplicationRecord
    # Associations
    has_many :city_commodities, dependent: :destroy
    has_many :transactions, dependent: :destroy
 has_many :npcs, primary_key: :name, foreign_key: :city_name, class_name: 'Npc'
    # Validations
    validates :name, presence: true, uniqueness: true
    belongs_to :shard, optional: true

    FOOD_CONSUMPTION_RATE = 0.1
    WOOD_CONSUMPTION_RATE = 0.07
    STONE_CONSUMPTION_RATE = 0.03
    METAL_CONSUMPTION_RATE = 0.01

    def consume_commodities!
      consume_wood!
      consume_food!
      consume_metal!
      consume_stone!
      save!
    end


    # Adjust prices based on commodity supply
    def adjust_prices!
      city_commodities.each do |commodity|
        supply = commodity.weight # or quantity if applicable
        base_price = commodity.base_price
  
        new_price = if supply >= 1000
                      0.0
                    elsif supply.zero?
                      base_price * 1.05
                    else
                      (base_price * 1.05) * (1.0 - supply / 1000.0)
                    end
  
        commodity.update!(current_price: new_price)
      end
    end
  
    # Calculate adjusted price based on supply
    def calculate_adjusted_price(base_price, supply)
      max_supply_cap = 1000.0
  
      if supply >= max_supply_cap
        0.0
      elsif supply <= 0.0
        base_price * 1.05
      else
        factor = 1.0 - (supply / max_supply_cap)
        (base_price * 1.05) * factor
      end
    end
  


    # Process a transaction and update commodity supplies and prices
    def process_transaction!(transaction)
      transaction.transaction_items.each do |item|
        commodity = city_commodities.find_or_initialize_by(
          category: item.category,
          subcategory: item.subcategory,
          item_name: item.item_name
        )
  
        # Update commodity supply based on the transaction
 
        if item.weight.present?
          commodity.weight += item.weight
        elsif item.quantity.present?
          commodity.quantity += item.quantity
        end
  
        commodity.save!
      end
  
      # Recalculate prices after the transaction
      adjust_prices!
    end

    def price_trend
      price_histories.order(:recorded_at).pluck(:recorded_at, :price)
    end
  
  
    private

    
    def consume_wood!
      consume_commodity(
        category: "wood",
        consumption_rate: WOOD_CONSUMPTION_RATE,
        supply_column: :wood_supply
      )
    end

    def consume_food!
      consume_commodity(
        category: "food",
        consumption_rate: FOOD_CONSUMPTION_RATE,
        supply_column: :food_supply
      )
    end
  
    def consume_metal!
      consume_commodity(
        category: "metal",
        consumption_rate: METAL_CONSUMPTION_RATE,
        supply_column: :metal_supply
      )
    end

    def consume_stone!
      consume_commodity(
        category: "stone",
        consumption_rate: STONE_CONSUMPTION_RATE,
        supply_column: :stone_supply
      )
    end

    def consume_commodity(category:, consumption_rate:, supply_column:)
      return if population <= 0
  
      # Calculate total consumption for the commodity
      total_consumption = (population * consumption_rate).round(2)
  
      # Deduct from City's aggregate supply
      self[supply_column] = [self[supply_column] - total_consumption, 0].max
  
      # Deduct from CityCommodity records
      to_consume = total_consumption
      commodities = city_commodities.where(category: category).order(weight: :desc)
  
      commodities.each do |commodity|
        break if to_consume <= 0
  
        if commodity.weight > 0
          used_weight = [commodity.weight, to_consume].min
          commodity.weight = commodity.weight - used_weight
          commodity.save! # Persist changes to the commodity record
          to_consume -= used_weight
        end
      end
  
      Rails.logger.info("City #{name} consumed #{total_consumption} units of #{category}. Remaining #{supply_column}: #{self[supply_column].round(2)}.")
    end


    def record_price_history
      price_histories.create(price: current_price, recorded_at: Time.current)
    end
   
  end
  
  