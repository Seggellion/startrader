module Api
    class NpcsController < ApplicationController
      # POST /api/npcs
      skip_before_action :verify_authenticity_token
      before_action :authenticate_api!

      def create
        npc = Npc.new(npc_params)
        
        if npc.save
          city = City.find_by(name: npc.city_name)
          
          if city
            city.increment!(:population) # Automatically updates and saves the city's population
          else
            # Optionally, create a new city if it doesn't exist
            city = City.create(name: npc.city_name, population: 1)
          end
          
          render json: { message: 'NPC registered successfully.', npc: npc }, status: :created
        else
          render json: { errors: npc.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/npcs/:id
      def destroy
        npc = Npc.find_by(npc_id: params[:id])
        
        if npc
          city = City.find_by(name: npc.city_name)
          city.decrement!(:population) if city && city.population > 0
          npc.destroy
          render json: { message: 'NPC removed successfully.' }, status: :ok
        else
          render json: { error: 'NPC not found.' }, status: :not_found
        end
      end
  
      private
  
      def authenticate_api!
        # 1) Grab the token from HTTP headers
        #    - "Authorization" is typical, but you can also use "X-API-Token"
        incoming_token = request.headers["Authorization"] 


        # Or if you prefer: request.headers["X-API-Token"]
        # 2) Check against our stored Setting
        valid_token = Setting.get("britannia_api_token")
  
        # e.g. If you choose a "Bearer" scheme:
        # Expect "Authorization: Bearer ABCDEF..."
        # We'll strip off "Bearer " and compare the rest:
        if incoming_token.blank? ||
           !incoming_token.start_with?("Bearer ") ||
           incoming_token.split(" ").last != valid_token
  
          render json: { error: "Unauthorized" }, status: :unauthorized
        end
      end

      def npc_params
        params.require(:npc).permit(:npc_id, :npc_type, :city_name, :name, :description, :level, :health, :mana, :is_active, :spawn_location)
      end
      
    end
  end
  