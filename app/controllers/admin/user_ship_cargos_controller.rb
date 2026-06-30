module Admin
  class UserShipCargosController < ApplicationController
    def destroy
      cargo = UserShipCargo.find(params[:id])
      user_ship = cargo.user_ship

      cargo.destroy

      redirect_back fallback_location: edit_admin_user_ship_path(user_ship), notice: "Cargo removed successfully."
    end
  end
end
