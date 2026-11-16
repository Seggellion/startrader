module Api
    class TickController < ApplicationController
      # M06 / S1 (F-10): tick mutation requires the integration secret.
      include SecretGuidAuth
      skip_before_action :verify_authenticity_token
  
      # POST /api/set_tick
      def set
        # Tick.set_current never existed; setting an arbitrary tick is not
        # supported. Return a clear answer instead of a NoMethodError.
        render json: { error: "Setting the tick is not supported; use the admin tick controls.",
          current_tick: Tick.current }, status: :not_implemented
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
  