module Admin
    class UserShipsController < ApplicationController
      def index
        @user_ships = UserShip.all
      end
  
      def new
        @user_ship = UserShip.new
      end
  
      def create
        @user_ship = UserShip.new(user_ship_params)


        if @user_ship.save
          redirect_to admin_user_ships_path, notice: 'UserShip was successfully created.'
        else
          render :new
        end
      end
  
      def edit
        @user_ship = UserShip.find_by_id(params[:id])
        @user_ship_cargos = @user_ship.user_ship_cargos.includes(:commodity)

      end
  
      def update
        @user_ship = UserShip.find_by_id(params[:id])
      
        # Update the user_ship attributes first
        if @user_ship.update(user_ship_params)
          # If the user_ship has content, process the ActionText content to replace <h1> with <h2>

          redirect_to edit_admin_user_ship_path(@user_ship), notice: 'UserShip was successfully updated.'
        else
          render :edit, alert: 'Failed to update the user_ship.'
        end
      end
          


      
      def delete_all
        UserShip.where(classification:"user_ship").destroy_all
        redirect_to admin_user_ships_path, notice: 'All user_ships have been deleted successfully.'
      end
  
      def destroy
        @location = UserShip.find(params[:id])
        @location.destroy
        redirect_to admin_user_ships_path, notice: 'UserShip was successfully deleted.'
      end
  
      private
  
      def set_user_ship
        
        @user_ship = UserShip.find(params[:id])
      end

      def convert_h1_to_h2(html)
        # A simplistic approach using gsub:
        html.gsub(/<h1>/, "<h2>").gsub(/<\/h1>/, "</h2>")
      end

      def user_ship_params
        params.require(:user_ship).permit(
          :shard_name,
          :location_name,
          :status
        )
      end
      
    end
  end
  