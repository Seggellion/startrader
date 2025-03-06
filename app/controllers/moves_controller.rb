# app/controllers/moves_controller.rb
class MovesController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      user_ship = user.user_ships.find_by(id: params[:user_ship_id]) || user.user_ships.order(updated_at: :desc).first
  byebug
      # ✅ If still no ship, return an error
      if user_ship.nil?
        return render json: { error: "No ship found for user #{username}." }, status: :unprocessable_entity
      end
      destination = Location.find(params[:location_id])
  
      TravelService.new(user_ship: user_ship, to_location: destination).call
  
      render json: { status: 'travel_started', user_ship_id: user_ship.id }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
  