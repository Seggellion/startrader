# app/services/travel_service.rb
class TravelService
  DEFAULT_WINDOW_PERCENT = 15

  attr_reader :user_ship, :to_location, :travel_guid, :rabbitmq_environment

  def initialize(user_ship:, to_location:, travel_guid:, from_location: nil, interdict_window_percent: nil, start_tick: nil, rabbitmq_environment: nil, request_context: nil)
    @request_context = request_context
    @user_ship = user_ship
    @from_location = from_location || user_ship.location
    @to_location = to_location
    @travel_guid = travel_guid
    @interdict_window_percent = interdict_window_percent || Setting.get("interdiction_window_percent") || DEFAULT_WINDOW_PERCENT
    @start_tick = start_tick
    # Blank means "keep the historical production behaviour"; anything that is
    # not a supported environment fails here rather than at arrival time.
    @rabbitmq_environment = RabbitmqConnection.normalize!(rabbitmq_environment)
  end

  def call
    raise ArgumentError, "travel_guid is required." if travel_guid.blank?
    context = @request_context || {kind:'ordinary',destination_id:to_location.id,origin_id:@from_location&.id,
      rabbitmq_environment:rabbitmq_environment}
    TravelLifecycle.with_ship(user_ship) do
      replay = TravelRequestReceipt.replay!(travel_guid,user_ship,context)
      next replay if replay
      start_tick = @start_tick || OrbitalState.current_tick!
      TravelLifecycle.assert_free!(user_ship,start_tick)
      raise "Current location not found for ship." if @from_location.nil?
      raise "Ship is already at that location." if @from_location&.id == to_location.id

      stored_location = user_ship.location || Location.find_by(name: user_ship.location_name)
      if stored_location.present? && stored_location.id != @from_location.id
        raise "Ship is at #{stored_location.name}, not #{@from_location.name}."
      end

      player_location=user_ship.shard_user&.current_location
      if player_location && stored_location && player_location.id != stored_location.id
        raise TravelLifecycle::Error.new('location_mismatch',"Ship is at #{stored_location.name}, but player is at #{player_location.name}.")
      end

      # Physical separation and validation use this one captured departure tick.
      # The calculator owns the 1 Gm/tick, ceiling and minimum-duration policy.
      duration = TravelTimeCalculator.new(
        ship: user_ship.ship,
        from_location: @from_location,
        to_location: to_location,
        start_tick: start_tick
      ).calculate

      arrival_tick = TravelLifecycle.deadline!(start_tick,duration)

      TravelRequestReceipt.lock_guid!(travel_guid)
      replay = TravelRequestReceipt.replay!(travel_guid,user_ship,context)
      next replay if replay

      # Saved journeys retain these values independently of later rates.
      travel = ShipTravel.create!(
        user_ship: user_ship,
        from_location: @from_location,
        to_location: to_location,
        travel_guid: travel_guid,
        departure_tick: start_tick,
        arrival_tick: arrival_tick,
        total_duration_ticks: duration,
        interdict_window_percent: @interdict_window_percent,
        rabbitmq_environment: @rabbitmq_environment
      )

      user_ship.update!(location_name: @from_location.name, status: "in_transit")
      user_ship.shard_user&.update_current_location!(@from_location)
      TravelRequestReceipt.record!(travel,context)
      travel
    end
  end
end
