# app/controllers/moves_controller.rb
class MovesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      user_ship = current_user.user_ships.find(params[:user_ship_id])
      destination = Location.find(params[:location_id])
  
      TravelService.new(user_ship: user_ship, to_location: destination).call
  
      render json: { status: 'travel_started', user_ship_id: user_ship.id }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
  