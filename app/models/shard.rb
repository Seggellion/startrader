class Shard < ApplicationRecord
    # Associations
    has_many :cities, dependent: :destroy
    has_many :city_commodities, dependent: :destroy
    has_many :npcs, dependent: :destroy
    has_many :transactions, dependent: :destroy
    has_many :shard_users, dependent: :destroy
    has_many :users, through: :shard_users
  
    # Validations
    validates :name, presence: true, uniqueness: true
    validates :region, presence: true
  
    # Scopes
    scope :with_active_npcs, -> { includes(:npcs).where(npcs: { is_active: true }) }
  
    # Callbacks
    before_save :sanitize_name
  
    private
  
    # Ensure the shard name is properly formatted
    def sanitize_name
      self.name = name.strip.titleize
    end
  end
  