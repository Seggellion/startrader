module Admin
  class UserShipsController < ApplicationController
    before_action :set_user_ship, only: [:edit, :update, :destroy]
    before_action :load_form_options, only: [:edit, :update]

    def index
      @user_ships = UserShip.includes(:user, :ship, :shard).order(updated_at: :desc)
    end

    def new
      @user_ship = UserShip.new
    end

    def create
      @user_ship = UserShip.new(user_ship_params)

      if @user_ship.save
        redirect_to admin_user_ships_path, notice: "UserShip was successfully created."
      else
        render :new
      end
    end

    def edit
      load_user_ship_details
    end

    def update
      if @user_ship.update(user_ship_params)
        redirect_to edit_admin_user_ship_path(@user_ship), notice: "UserShip was successfully updated."
      else
        load_user_ship_details
        render :edit, status: :unprocessable_entity
      end
    end

    def delete_all
      UserShip.where(classification: "user_ship").destroy_all
      redirect_to admin_user_ships_path, notice: "All user_ships have been deleted successfully."
    end

    def destroy
      @user_ship.destroy
      redirect_to admin_user_ships_path, notice: "UserShip was successfully deleted."
    end

    private

    def set_user_ship
      @user_ship = UserShip
        .includes(
          :user,
          :ship,
          :shard,
          :shard_user,
          :location,
          { user_ship_cargos: :commodity },
          { active_travel: [:from_location, :to_location] },
          { ship_travel: [:from_location, :to_location] }
        )
        .find(params[:id])
    end

    def load_user_ship_details
      @user_ship_cargos = @user_ship.user_ship_cargos.to_a
      @active_travel = @user_ship.active_travel
      @ship_travel = @user_ship.ship_travel
    end

    def load_form_options
      @shards = Shard.order(:name)
      @shard_users = ShardUser.includes(:user).order(:id)
      @location_names = Location.order(:name).pluck(:name)
      @status_options = (UserShip.distinct.pluck(:status) + [@user_ship.status, "docked", "in_transit", "interdicted"]).compact.uniq.sort
    end

    def user_ship_params
      params.require(:user_ship).permit(
        :shard_name,
        :location_name,
        :status,
        :shard_id,
        :shard_user_id,
        :ship_slug,
        :total_scu,
        :used_scu
      )
    end
  end
end
