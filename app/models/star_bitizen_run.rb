class StarBitizenRun < ApplicationRecord
  belongs_to :user
  belongs_to :user_ship_cargo, optional: true
  belongs_to :commodity
  belongs_to :user_ship

  # Locations now referenced by name instead of ID
  belongs_to :buy_location, class_name: 'Location', foreign_key: 'buy_location_name', primary_key: 'name', optional: true
  belongs_to :sell_location, class_name: 'Location', foreign_key: 'sell_location_name', primary_key: 'name', optional: true

  # New association for the game shard (tracked by name)
  belongs_to :shard_instance, class_name: 'Shard', foreign_key: 'shard', primary_key: 'name', optional: true

  validates :profit, :scu, numericality: { greater_than_or_equal_to: 0 }

  # Calculate distance dynamically based on orbital mechanics
  def distance
    return nil unless buy_location && sell_location

    # Placeholder for orbital distance calculation logic
    Math.sqrt((buy_location.periapsis - sell_location.periapsis)**2)
  end
end
