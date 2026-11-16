class ShipTravelArrivalProcessor
  def initialize(travel:, current_tick:Tick.current, notify:true)
    @travel,@current_tick,@notify=travel,current_tick,notify
  end
  def call
    return @travel if @travel.destroyed?
    TravelLifecycle.with_ship(@travel.user_ship) do
      TravelRequestReceipt.lock_guid!(@travel.travel_guid)
      @travel.lock!
      next unless @travel.due_for_arrival?(@current_tick)
      raise TravelLifecycle::Error.new('invalid_state','Travel needs review.') if TravelState.new(@travel,tick:@current_tick).invalid?
      # Multiple unfinished journeys are never resolved by choosing one arbitrarily.
      if @travel.user_ship.ship_travels.where(completed_at_tick:nil).count != 1
        raise TravelLifecycle::Error.new('invalid_state','Duplicate unfinished journeys need review.')
      end
      # M03 / Q1: departure normalizes the ship's player to the origin and status
      # cannot move either record while the journey is unfinished, so arrival
      # lands the ship and its own player together. (The former "player still at
      # origin" condition left players behind whenever any writer diverged them.)
      LocationSync.both!(ship:@travel.user_ship, player:@travel.user_ship.shard_user,
        location:@travel.to_location, source:'travel_arrival', status:arrival_status)
      TravelRequestReceipt.finish!(@travel,'completed',@current_tick)
      if @notify
        TravelArrivalEvent.create!(event_guid:SecureRandom.uuid,travel_guid:@travel.travel_guid,
          rabbitmq_environment:@travel.rabbitmq_environment,payload:RabbitmqSender.ship_report_payload(@travel))
      end
      receipt_id = TravelRequestReceipt.find_by!(travel_guid:@travel.travel_guid).id
      trace = "event=travel_completed receipt_id=#{receipt_id} user_ship_id=#{@travel.user_ship_id} " \
        "from_location_id=#{@travel.from_location_id} to_location_id=#{@travel.to_location_id} " \
        "completed_at_tick=#{@current_tick} rabbitmq=#{@travel.rabbitmq_environment}"
      @travel.cleanup_after_arrival!(@current_tick)
      ActiveRecord.after_all_transactions_commit { Rails.logger.info(trace) }
    end
    @travel
  rescue ActiveRecord::RecordNotFound
    @travel
  end
  private
  def arrival_status
    {'space_station'=>'docked','planet'=>'in orbit','moon'=>'in orbit','city'=>'landed','outpost'=>'landed'}
      .fetch(@travel.to_location.classification,'floating')
  end
end
