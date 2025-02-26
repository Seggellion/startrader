module Api
    class TransactionsController < ApplicationController
      protect_from_forgery with: :null_session
      before_action :authenticate_api!

      def create
        city_name = params[:city_name]
        player_uuid = params[:player_uuid]
        npc_id = params[:npc_id]
        npc_name = params[:npc_name]
        transaction_type = params[:transaction_type]
        transaction_items = params[:transaction_items] || []
        client_total_price = params[:total_price]
        recipe_checksum = params[:recipe_checksum].to_f
        deducted_commodities = params[:deducted_commodities] || []


        city = City.find_by(name: city_name)
        return render json: { error: "City not found" }, status: :unprocessable_entity unless city
  
        npc = Npc.find_by(npc_id: npc_id)
        return render json: { error: "NPC not found" }, status: :unprocessable_entity unless npc
  
        shard = Shard.find_or_create_by(name: "Britannia")
  
        total_price = 0.0
        created_transaction_items = []
        
        transaction_items.each do |item|
          item_name = item["item_name"]
          quantity = item["quantity"] || 1
          weight = item["weight"] || 0.0
           
          if transaction_type == "purchase"
            # Deduct commodities for purchases
            #if weight > 0.0
            #  commodity.weight -= weight
            #else
            #  commodity.quantity -= quantity
            #end

            unless validate_and_deduct_commodities(city, deducted_commodities, recipe_checksum)
              return render json: { error: "Invalid commodity deductions" }, status: :unprocessable_entity
            end

            price = item["price"]&.to_f || 0.0
          total_price += price * quantity
  
          elsif transaction_type == "sell"
            # Add commodities for sales

            first_word = item_name.downcase.split.first

            commodity = city.city_commodities.find_by("LOWER(item_name) = ?", first_word)
          next unless commodity
  
          price_per_unit = commodity.current_price || 0.0
          price = if weight > 0.0
                    price_per_unit * weight
                  else
                    price_per_unit * quantity
                  end
  
          total_price += price

            if weight > 0.0
              commodity.weight += weight
            else              
              commodity.quantity += quantity
            end
            commodity.save!
            city.save!
          end
          
          created_transaction_items << {
            item_name: item_name,
            quantity: quantity,
            weight: weight,
            price: price
          }
        end
  
        MarketManager.adjust_prices(city)
        
        transaction = city.transactions.create!(
          player_uuid: player_uuid,
          npc_id: npc_id,
          npc_name: npc_name,
          shard_id: shard.id,
          transaction_type: transaction_type,
          total_price: total_price
        )
  
        transaction.transaction_items.create!(created_transaction_items)
  
        render json: {
          success: true,
          total_gold: total_price,
          transaction_type: transaction_type,
          message: "Transaction processed successfully."
        }
      end
  
      private
  
      def validate_and_deduct_commodities(city, deducted_commodities, client_checksum)
        # Calculate total deduction sum from commodities
        total_deductions = deducted_commodities.sum { |c| c["quantity"].to_f }

        unless total_deductions.round(2) == client_checksum.round(2)
          Rails.logger.warn("Checksum mismatch: Client=#{client_checksum}, Server=#{total_deductions}")
          return false
        end
      
 
        deducted_commodities.each do |deduction|
          material = deduction["item_name"].downcase
          original_quantity = deduction["quantity"].to_f
          weight = (original_quantity * 0.7).round(2)
      
          commodity = city.city_commodities.find_by("LOWER(item_name) = ?", material)
          unless commodity && commodity.weight >= weight
            Rails.logger.warn("Insufficient commodity: #{material}, Needed=#{weight}, Available=#{commodity&.weight}")
            return false
          end
      

          commodity.weight -= weight
          commodity.save!
        end


        true
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

      def transaction_params
        params.require(:transaction).permit(
          :player_uuid, :transaction_type, :total_price, :city_name, :recipe_checksum,
          transaction_items_attributes: [:item_name, :quantity, :price],
          deducted_commodities: [:item_name, :quantity]
        )
      end
    end
  end
  