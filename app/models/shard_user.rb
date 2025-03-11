class ShardUser < ApplicationRecord
  belongs_to :user
  belongs_to :shard, primary_key: :name, foreign_key: :shard_name, optional: true

  # Store inventory and currency as JSON
  store :inventory, coder: JSON
  store :currency, coder: JSON # ✅ Add missing store declaration
  store :stats, coder: JSON
  store :last_location, coder: JSON


  before_save :initialize_serialized_fields # ✅ Runs before every save

  validate :currency_not_nil
  validate :inventory_not_nil

  def initialize(attributes = {})
    super
    self.currency = {} if self.currency.nil?
    self.inventory = {} if self.inventory.nil?
    self.last_location = {} if last_location.nil?
  end

  def add_to_inventory(item, quantity)
    self.inventory[item] ||= 0
    self.inventory[item] += quantity
    save
  end

  def spend_currency(type, amount)
    self.currency[type] ||= 0
    if self.currency[type] >= amount
      self.currency[type] -= amount
      save
    else
      raise "Insufficient funds for #{type}"
    end
  end

  # Returns all UserShip records where the shard_name matches this ShardUser's shard.name
  def user_ships
    
    UserShip.where(user_id: user_id, shard_name: shard_name)
  end

  def update_credits(amount)
    new_balance = wallet_balance.to_f + amount.to_f
    
    update(wallet_balance: new_balance)
  end

  private

  def initialize_serialized_fields
    self.inventory = {} if inventory.nil? # ✅ Fix: Use `=` instead of `||=`
    self.currency = {} if currency.nil? # ✅ Fix: Use `=` instead of `||=`
  end

  def currency_not_nil
    errors.add(:currency, "must not be nil") if currency.nil?
  end

  def inventory_not_nil
    errors.add(:inventory, "must not be nil") if inventory.nil?
  end
end
