class LocationsController < ApplicationController

  #  def show
  #    location = Location.find(params[:id])
  #    render json: location
  #  end


   def index
    system_name = params[:star].presence || "Stanton"

    # Fetch the star (if modeled as a Location with classification 'star_system')
    star = Location.where(classification: "star_system", star_system_name: system_name).first

    # Fetch planets in that system; preload the star association for starmass
    planets = Location.where(classification: "planet", star_system_name: system_name)

    payload = []

    # Include the star first (so the client can register it before planets)
    if star
      payload << {
        id: star.id,
        attributes: {
          'name': star.name,
          'classification': 'star_system',
          'system': star.star_system_name,
          'mass': star.mass,
          'starmass': nil
        }
      }
    end

    # Then include planets
    planets.each do |location|
      payload << {
        id: location.id,
        attributes: {
          'name': location.name,
          'classification': 'planet',
          'system': location.star_system_name,
          'apoapsis': location.apoapsis,
          'periapsis': location.periapsis,
          'mass': location.mass,
          'starmass': location.star&.mass
        }
      }
    end

    render json: payload
  end



    def show
      user_ship = current_user.user_ships.find(params[:id])
      active_travel = user_ship.active_travel
  
      if active_travel
        render json: {
          in_transit: true,
          from_location: active_travel.from_location.name,
          to_location: active_travel.to_location.name,
          departure_tick: active_travel.departure_tick,
          arrival_tick: active_travel.arrival_tick,
          current_tick: Tick.current
        }
      else
        render json: {
          in_transit: false,
          location: user_ship.location.name
        }
      end
    end


  end
  