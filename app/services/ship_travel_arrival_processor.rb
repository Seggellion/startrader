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
      @travel.user_ship.update!(location_name:@travel.to_location.name,status:arrival_status)
      player=@travel.user_ship.shard_user
      if player && (player.current_location.nil? || player.current_location.id==@travel.from_location_id)
        player.update_current_location!(@travel.to_location)
      end
      TravelRequestReceipt.finish!(@travel,'completed',@current_tick)
      if @notify
        TravelArrivalEvent.create!(event_guid:SecureRandom.uuid,travel_guid:@travel.travel_guid,
          rabbitmq_environment:@travel.rabbitmq_environment,payload:RabbitmqSender.ship_report_payload(@travel))
      end
      @travel.cleanup_after_arrival!(@current_tick)
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
