class Location < ApplicationRecord
    belongs_to :parent, class_name: 'Location', optional: true
    has_many :children, class_name: 'Location', foreign_key: 'parent_id', dependent: :nullify

    has_many :terminals

 

    has_many :production_facilities
    has_many :commodities, through: :production_facilities
  
    has_many :star_bitizen_runs, foreign_key: :buy_location_id
    has_many :star_bitizen_runs, foreign_key: :sell_location_id
  
    validates :name, presence: true
  
    # Example method to get available commodities at this location
    def available_commodities
      production_facilities.includes(:commodity).map(&:commodity)
    end
  end
  