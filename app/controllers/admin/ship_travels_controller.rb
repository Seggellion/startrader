module Admin
  class ShipTravelsController < ApplicationController
    before_action :private_response
    protect_from_forgery with: :exception
    def index
      @recent_resumes=TravelResumeAction.order(id: :desc).limit(20)
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
      @resume_review=ResumeInterdiction.review(@ship_travel)
      @resume_actions=TravelResumeAction.where(ship_travel_id:@ship_travel.id).order(id: :desc).limit(20)
    end
    def resume
      result=ResumeInterdiction.call(id:params[:id],review_token:params[:review_token],
        actor:current_user,reason:params[:reason])
      notice=result.replayed ? 'This interdiction was already resumed; no further change was made.' :
        "Journey resumed with #{result.action.remaining_ticks} ticks remaining. Arrival tick #{result.action.arrival_tick}."
      redirect_to admin_ship_travels_path,notice:notice,status: :see_other
    rescue TravelLifecycle::Error => error
      begin
        show
      rescue ActiveRecord::RecordNotFound
        return redirect_to admin_ship_travels_path,alert:error.message,status: :see_other
      end
      flash.now[:alert]=error.message
      render :show,status: :unprocessable_entity
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_ship_travels_path,alert:'Journey is no longer available. Check the recent resume history.',status: :see_other
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
    def private_response
      response.set_header('Cache-Control','no-store')
    end
  end
end
