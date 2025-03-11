class StarBitizenRunsController < ApplicationController
    def index
      runs = StarBitizenRun.order(updated_at: :desc)
      render json: runs
    end
  
    def show
      run = StarBitizenRun.find(params[:id])
      render json: run
    end
  
    def create
      run = StarBitizenRun.new(run_params)
      if run.save
        render json: run, status: :created
      else
        render json: run.errors, status: :unprocessable_entity
      end
    end
  
    private
  
    def run_params
      params.require(:star_bitizen_run).permit(
        :user_id, :commodity_id, :profit, :scu, :twitch_channel, 
        :buy_location_id, :sell_location_id, :user_ship_cargo_id
      )
    end
  end
  