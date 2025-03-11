class Location < ApplicationRecord
 # Self-referential 'parent' association using `parent_name` to match the `name` of the parent
 belongs_to :parent, 
 class_name: 'Location', 
 primary_key: 'name', 
 foreign_key: 'parent_name', 
 optional: true,
 inverse_of: :children

# 'children' association to fetch all locations where this is the parent
has_many :children, 
class_name: 'Location', 
foreign_key: 'parent_name', 
primary_key: 'name',
inverse_of: :parent

    has_many :user_ships, primary_key: :name, foreign_key: :location_name, dependent: :nullify


    has_many :terminals

 
    # Using `location_name` as foreign key instead of `location_id`
    has_many :production_facilities, 
    primary_key: :name, 
    foreign_key: :location_name

    # Through association, linking to commodities via production facilities
    has_many :commodities, 
    through: :production_facilities, 
    source: :commodity
  
    has_many :star_bitizen_runs, foreign_key: :buy_location_id
    has_many :star_bitizen_runs, foreign_key: :sell_location_id
  
    validates :name, presence: true
  
    def distance_to(other_location, tick = Tick.current)
      # Calculate the current position using the advanced orbital mechanics
      
      position1 = PlanetPositionCalculator.calculate_position(self, tick)      
      position2 = PlanetPositionCalculator.calculate_position(other_location, tick)
      
    
      # Calculate the distance between the two points
      Math.sqrt((position2[:x] - position1[:x])**2 + (position2[:y] - position1[:y])**2)
    end
      
    def self.planets
      Location.where(classification:"planet")
    end

    def self.cities
      Location.where(classification:"city")
    end
    
    def space_station?
      classification == "space_station"
    end
    
    def self.stars
      @stars ||= Location.where(classification: "star_system").index_by(&:api_id)
    end
    
    def star
      Location.find_by(name: self.star_system_name)
    end
    
    # Example method to get available commodities at this location
    def available_commodities
      production_facilities.includes(:commodity).map(&:commodity)
    end
  end
  