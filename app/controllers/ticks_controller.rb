class TicksController < ApplicationController
    def index
      ticks = Tick.all
      render json: ticks
    end
  
    def create
      tick = Tick.new(tick_params)
      if tick.save
        tick.process_tick
        render json: tick, status: :created
      else
        render json: tick.errors, status: :unprocessable_entity
      end
    end
  
    private
  
    def tick_params
      params.require(:tick).permit(:sequence, :processed_at)
    end
  end
  