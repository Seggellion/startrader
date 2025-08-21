module Api
    class ShardUsersController < ApplicationController
      protect_from_forgery with: :null_session
      before_action :authenticate_api!
      before_action :set_shard_user, only: [:adjust_stats]
  
      # PATCH /api/shard_users/:id/adjust_stats
      def adjust_stats
        karma_adjustment = params[:karma].to_i
        fame_adjustment = params[:fame].to_i
  
        @shard_user.karma += karma_adjustment
        @shard_user.fame += fame_adjustment
  
        if @shard_user.save
          render json: { success: true, karma: @shard_user.karma, fame: @shard_user.fame }, status: :ok
        else
          render json: { error: "Failed to update user stats" }, status: :unprocessable_entity
        end
      end
  
      private
  
      def set_shard_user
        uid = params[:id]
        shard_id = params[:shard_id] # Shard association
        karma_adjustment = params[:karma].to_i
        fame_adjustment = params[:fame].to_i
        last_location = { x: params[:x].to_f, y: params[:y].to_f, z: params[:z].to_f } # Convert to floats

        return render json: { error: "Missing UID or Shard ID" }, status: :bad_request unless uid.present? && shard_id.present?
      
        # Find or create the user
        user = User.find_or_create_by(minecraft_uuid: uid) do |u|
          u.email = params[:email] || "temporary@star_trader.com" # Default email
        end
      
        # Find the shard user or build a new one if missing
        @shard_user = ShardUser.find_by(user: user, shard_id: shard_id) || ShardUser.new(user: user, shard_id: shard_id)
      
        # Explicitly call the method that initializes the required fields
        @shard_user.send(:initialize_serialized_fields)
      
        # Apply karma/fame adjustments
        @shard_user.karma ||= 0
        @shard_user.fame ||= 0
        @shard_user.karma += karma_adjustment
        @shard_user.fame += fame_adjustment
        @shard_user.last_location = last_location

        if @shard_user.save
          render json: { success: true, karma: @shard_user.karma, fame: @shard_user.fame }, status: :ok
        else
          render json: { error: "Failed to update shard user", details: @shard_user.errors.full_messages }, status: :unprocessable_entity
        end
      end
      
      
      
      def authenticate_api!
        token = request.headers["Authorization"]
        if token.blank? || !token.start_with?("Bearer ") || 
           (token.split(" ").last != Setting.get("britannia_api_token"))
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end
    end
  end
  