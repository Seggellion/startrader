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

has_many :departing_ship_travels, 
           class_name: 'ShipTravel', 
           foreign_key: :from_location_id, 
           dependent: :destroy

  has_many :arriving_ship_travels, 
           class_name: 'ShipTravel', 
           foreign_key: :to_location_id, 
           dependent: :destroy

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
    validate :preserve_calibrated_identity, on: :update
    before_destroy :protect_calibration_record, prepend: true
  
    def distance_to(other_location, tick = nil)
      raise Orbital::Unavailable, 'Direct distance requires one system frame' unless
        star_system_name.present? && star_system_name == other_location.star_system_name
      OrbitalState.snapshot(tick: tick || OrbitalState.current_tick!, systems: [star_system_name]).distance(id, other_location.id)
    end
      
    def self.planets
      Location.where(classification:"planet")
    end

    def self.moons
      Location.where(classification:"moon")
    end

    def self.space_stations
      Location.where(classification:"space_station")
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

    private

    def protect_calibration_record
      return unless OrbitalState.catalog.entry_for(attributes)
      errors.add(:base, 'Calibrated orbital records cannot be deleted')
      throw :abort
    rescue Orbital::Unavailable => error
      errors.add(:base, error.message)
      throw :abort
    end

    def preserve_calibrated_identity
      previous = attributes.merge(attributes_in_database)
      entry = OrbitalState.catalog.entry_for(previous)
      return unless entry
      unless OrbitalState.catalog.entry_for(attributes) == entry
        errors.add(:base, 'Calibrated orbital identity cannot be changed by an importer or admin edit')
      end
    rescue Orbital::Unavailable => error
      errors.add(:base, error.message)
    end
  end
  