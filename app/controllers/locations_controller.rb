class LocationsController < ApplicationController

  #  def show
  #    location = Location.find(params[:id])
  #    render json: location
  #  end


  def index
    if params[:star].present?
      @locations = Location.planets.where(star_system_name: params[:star])
    else
      @locations = Location.planets.where(star_system_name: "Stanton")
    end

    render json: @locations.map { |location|
      {
        id: location.id,
        attributes: {
          'name': location.name,
          'classification': location.classification,
          'system': location.star_system_name,
          'apoapsis': location.apoapsis,
          'periapsis': location.periapsis,
          'mass': location.mass,
          'starmass': location.star.mass
        }
      }
    }
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
  