class Npc < ApplicationRecord
    # Validations
    validates :npc_id, presence: true, uniqueness: true
    validates :npc_type, presence: true
    validates :city_name, presence: true
    belongs_to :city, primary_key: :name, foreign_key: :city_name, optional: true

    # Scopes (Optional)
    scope :active, -> { where(is_active: true) }
    scope :by_city, ->(city) { where(city_name: city) }
  
    # Example method to parse inventory (if needed)
    def inventory_items
      inventory['items'] || []
    end
  
    # Example method to parse stats (if needed)
    def stat_value(key)
      stats[key.to_s] || 0
    end
  end
  