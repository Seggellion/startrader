# app/controllers/admin/users_controller.rb
module Admin
  class UsersController < ApplicationController
    before_action :require_admin
    before_action :set_user, only: [:show, :edit, :update]

    def index
      @users = User.includes(user_ships: [:ship, :user_ship_cargos, { active_travel: :to_location }])
                   .order(created_at: :desc)
    end

    def show
    end

    def edit
    end

    def update
      if @user.update(user_params)
        redirect_to admin_user_path(@user), notice: "User was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = User.includes(user_ships: [:ship, :user_ship_cargos, { active_travel: :to_location }])
                  .find(params[:id])
    end

    def user_params
      permitted_attributes = [
        :username,
        :twitch_id,
        :user_type,
        :first_name,
        :last_name,
        :country,
        :wallet_balance
      ]
      permitted_attributes << :avatar if @user.has_attribute?(:avatar) || (@user.respond_to?(:avatar) && @user.avatar.respond_to?(:attached?))

      permitted = params.require(:user).permit(*permitted_attributes)
      permitted[:user_type] = normalized_user_type(permitted[:user_type]) if permitted.key?(:user_type)
      permitted
    end

    def normalized_user_type(value)
      case value.to_s
      when "0", "admin"
        "admin"
      when "1", "player", "user"
        "player"
      else
        value
      end
    end
  end
end
