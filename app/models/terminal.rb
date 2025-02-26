class Terminal < ApplicationRecord
    # We want to link terminals to locations via "code"
    belongs_to :location, optional: true

    # Custom logic to determine the related location based on the available IDs
   # before_save :assign_location
  
    private
  
    def assign_location
      # Try to match by space station ID first
  
      self.location = Location.find_by(api_id: id_space_station) if id_space_station.positive?
  
      # If no space station, try matching by city ID
      self.location ||= Location.find_by(api_id: id_city) if id_city.positive?

      # If no space station, try matching by city ID
      self.location ||= Location.find_by(api_id: id_outpost) if id_outpost.positive?
    end

  end
  