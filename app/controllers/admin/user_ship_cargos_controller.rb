module Admin
    class UserShipCargosController < ApplicationController
  
  
      def destroy
        cargo = UserShipCargo.find(params[:id])
        cargo.destroy
        redirect_back fallback_location: admin_user_ship_path(cargo.user_ship), notice: "Cargo removed successfully."
      end
  
    end
  end
  