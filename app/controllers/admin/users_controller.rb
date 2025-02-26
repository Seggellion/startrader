# app/controllers/admin/users_controller.rb
module Admin
    class UsersController < ApplicationController
      before_action :require_admin
      before_action :set_user, only: [:edit, :update]
  
      def index
        @users = User.all
      end
  
      def edit
        # The @user instance variable is set by the set_user method
      end
  
      def update
        if @user.update(user_params)
          redirect_to admin_users_path, notice: 'User was successfully updated.'
        else
          render :edit
        end
      end
  
      private
  
      def set_user
        @user = User.find(params[:id])
      end
  
      def user_params
        params.require(:user).permit(:name, :email, :user_type)
      end
    end
  end
  