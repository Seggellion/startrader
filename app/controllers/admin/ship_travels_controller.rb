module Admin
  class ShipTravelsController < ApplicationController
    before_action :read_only_diagnostics
    def index
      @tick=Tick.order(:id).pick(:current_tick) || 0
      scope=ShipTravel.where(completed_at_tick:nil)
      @filter=params[:state].to_s
      scope=case @filter
      when 'scheduled' then scope.where(is_paused:false).where('arrival_tick > ?',@tick)
      when 'interdicted' then scope.where(is_paused:true)
      when 'awaiting_completion' then scope.where(is_paused:false).where('arrival_tick > 0 AND arrival_tick <= ?',@tick)
      else scope
      end
      @ship_travels=scope.includes(:from_location,:to_location,user_ship:[:user,:ship,:shard_user])
        .where('ship_travels.id > ?',params[:after].to_i).order(:id).limit(100).to_a
      ids=@ship_travels.map(&:user_ship_id)
      duplicates=ShipTravel.where(user_ship_id:ids,completed_at_tick:nil).group(:user_ship_id).having('count(*) > 1').count
      @states=@ship_travels.to_h{|t|[t.id,TravelState.new(t,tick:@tick,duplicate:duplicates.key?(t.user_ship_id))]}
      @next_id=@ship_travels.last&.id if @ship_travels.size==100
      @ship_travels.select!{|t|@states[t.id].warnings.any?} if @filter=='needs_review'
    end
    def show
      @ship_travel=ShipTravel.includes(:from_location,:to_location,user_ship:[:user,:ship,:shard_user]).find(params[:id])
      duplicate=ShipTravel.where(user_ship_id:@ship_travel.user_ship_id,completed_at_tick:nil).count>1
      @state=TravelState.new(@ship_travel,duplicate:duplicate)
    end
    def edit
      show
      render :show
    end
    def new; head :method_not_allowed; end
    def create; head :method_not_allowed; end
    def update; head :method_not_allowed; end
    def destroy; head :method_not_allowed; end
    def delete_all; head :method_not_allowed; end
    private
    def read_only_diagnostics
      response.set_header('Cache-Control','no-store')
    end
  end
end
