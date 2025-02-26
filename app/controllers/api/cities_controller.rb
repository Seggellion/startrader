# app/controllers/api/cities_controller.rb
module Api
    class CitiesController < ApplicationController
      protect_from_forgery with: :null_session
      before_action :set_city, only: [:food_supply]
      before_action :authenticate_api!


      def food_supply

        if @city
          render json: { food_supply: @city.food_supply }, status: :ok
        else
          render json: { error: "City not found" }, status: :not_found
        end
      end


      def food_and_wood_supply
        city = City.find_by(name: params[:id])
      
        if city
          render json: { 
            food_supply: city.food_supply, 
            wood_supply: city.wood_supply 
          }, status: :ok
        else
          render json: { error: "City not found" }, status: :not_found
        end
      end
      

    # POST /api/cities/:id/consume_commodities
    def consume_commodities
      cities_data = []
      City.find_each do |city|
        city.update(population: city.npcs.count)
        city.consume_commodities!
        cities_data << {
          name: city.name,
          food_supply: city.food_supply,
          wood_supply: city.wood_supply,
          stone_supply: city.stone_supply,
          metal_supply: city.metal_supply
        }
      end
    
      render json: { success: true, message: "Commodities consumed for all cities", cities: cities_data }, status: :ok
    end

    # GET /api/cities/:id/starvation_status
    def starvation_status
      city = City.find_by(name: params[:id])
      return render json: { error: "City not found" }, status: :not_found unless city

      is_starving = city.is_starving? # If city is out of food
      render json: { city_name: city.name, starving: is_starving }, status: :ok
    end

    def starving
      # Suppose you have a City model with a scope or method to find starving cities
      starving_cities = City.where('food_supply < ?', 10) # or any condition you define
      # Build the JSON response
      data = {
        starving_cities: starving_cities.map { |city| { name: city.name } }
      }
      render json: data, status: :ok
    end


         # GET /api/cities/:city_name/price_trends
    def price_trends
      if @city
        render json: {
          city_name: @city.name,
          price_trends: @city.commodity_price_trends
        }, status: :ok
      else
        render json: { error: "City not found" }, status: :not_found
      end
    end
  
    def prices
      if @city
        render json: { city_name: @city.name, prices: @city.prices }, status: :ok
      else
        render json: { error: "City not found" }, status: :not_found
      end
    end

    
    def trade_data
      city = City.find_by(name: params[:id])      
      return render json: { error: "City not found" }, status: :not_found unless city
    
      # Get tech supply and available metals
      tech_supply = city.technology_supply
      metal_commodities = city.city_commodities.where(category: "metal").pluck(:item_name, :weight)
    
      # Fetch all relevant market prices in one query
      market_prices = city.city_commodities.pluck(:item_name, :current_price).to_h
    
      render json: {
        tech_supply: tech_supply,
        metal_commodities: metal_commodities,
        market_prices: market_prices
      }, status: :ok
    end
    



      def sync
        city_name = params[:city_name]

        
        city = City.find_or_create_by!(name: city_name)
        
        city.update!(
          population:  params[:population] || city.population,
          is_starving: params[:is_starving],
          food_supply: params[:food_supply], 
          wood_supply: params[:wood_supply]
        )
  
        # Update commodities
        (params[:commodities] || []).each do |c|
          CityCommodity.create!(
            city:       city,
            category:   c[:category],
            subcategory: c[:subcategory],
            item_name:  c[:item_name],
            quantity:   c[:quantity],
            weight:     c[:weight]
            # or update if you want a single row per item_name
          )
        end
  
        # Update leaderboard
        (params[:leaderboard] || []).each do |l|
          pc = PlayerContribution.find_or_create_by!(
            city:            city,
            player_uuid:     l[:player_uuid],
            player_name:     l[:player_name],
            commodity_type:  l[:commodity_type],
            commodity_name:  l[:commodity_name]
          )
          # Update totals
          pc.total_contribution += l[:total_contribution].to_f
          if l[:biggest_single].to_f > pc.biggest_single
            pc.biggest_single = l[:biggest_single].to_f
          end
          pc.save!
        end
  
        render json: { status: "ok" }, status: :ok
      end

      private
  
      def set_city
        # Assuming you identify cities by name
        @city = City.find_by(name: params[:id])
      end
      

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
  


    end
  end
  