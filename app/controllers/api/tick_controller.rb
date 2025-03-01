module Api
    class TickController < ApplicationController
      skip_before_action :verify_authenticity_token
  
      # POST /api/set_tick
      def set
        new_tick = params[:tick].to_i
        Tick.set_current(new_tick)
        render json: { 
          message: "Tick set to #{Tick.current}", 
          current_tick: Tick.current,
          current_sequence: Tick.current_sequence
        }
      end
  
      # POST /api/increment_tick
      def increment
        Tick.increment!
        render json: { 
          message: "Tick incremented", 
          current_tick: Tick.current,
          current_sequence: Tick.current_sequence
        }
      end
    end
  end
  