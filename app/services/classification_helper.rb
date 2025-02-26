# app/services/classification_helper.rb
module ClassificationHelper
    # Prioritized classification logic
    def determine_classification(data)
      return "space_station" if data['id_space_station'].to_i > 0
      return "outpost" if data['id_outpost'].to_i > 0
      return "city" if data['id_city'].to_i > 0
      return "poi" if data['id_poi'].to_i > 0
      return "moon" if data['id_moon'].to_i > 0
      return "planet" if data['id_planet'].to_i > 0
  
      # Special case for star systems
      if data['id_star_system'].to_i > 0 &&
         data['id_planet'].to_i.zero? &&
         data['id_moon'].to_i.zero? &&
         data['id_space_station'].to_i.zero? &&
         data['id_outpost'].to_i.zero? &&
         data['id_poi'].to_i.zero? &&
         data['id_city'].to_i.zero?
        return "star_system"
      end
  
      "unknown"
    end
  end
  