module Admin
  class ShardUsersController < ApplicationController
    before_action :set_shard_user, only: [:edit, :update, :destroy]
    before_action :load_form_options, only: [:new, :edit, :create, :update]

    def index
      @shard_users = ShardUser.includes(:user, :shard).order(updated_at: :desc)
    end

    def new
      @shard_user = ShardUser.new
    end

    def create
      @shard_user = ShardUser.new(shard_user_params)

      if @shard_user.save
        redirect_to admin_shard_users_path, notice: "ShardUser was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @shard_user.update(shard_user_params)
        redirect_to edit_admin_shard_user_path(@shard_user), notice: "ShardUser was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      ActiveRecord::Base.transaction do
        @shard_user.destroy!
      end

      redirect_to admin_shard_users_path, notice: "ShardUser was successfully deleted."
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      redirect_to admin_shard_users_path, alert: "ShardUser could not be deleted: #{e.message}"
    end

    private

    def set_shard_user
      @shard_user = ShardUser.includes(:user, :shard, user_ships: [:user_ship_cargos, :ship_travels]).find(params[:id])
    end

    def load_form_options
      @users = User.order(:username)
      @shards = Shard.order(:name)
    end

    def shard_user_params
      params.require(:shard_user).permit(
        :user_id,
        :shard_id,
        :wallet_balance,
        :karma,
        :fame,
        :murder_count
      )
    end
  end
end
