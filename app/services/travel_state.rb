require_relative '../../lib/travel_state_contract'
# Read-only classifier shared by diagnostics, status and availability.
class TravelState
  attr_reader :travel, :tick
  def initialize(travel, tick: (Tick.order(:id).pick(:current_tick) || 0), duplicate: false, player_location_name: nil)
    @travel, @tick, @duplicate = travel, tick, duplicate
    @player_location_name = player_location_name
  end

  def valid_pause?
    TravelStateContract.valid_pause?(travel.attributes)
  end

  def invalid?
    @duplicate || TravelStateContract.invalid?(travel.attributes)
  end

  def state
    @duplicate ? 'invalid' : TravelStateContract.state(travel.attributes,tick)
  end

  def label
    {'invalid'=>'Invalid travel state','completed'=>'Completed','interdicted'=>'Interdicted',
     'awaiting_completion'=>'Awaiting completion','scheduled'=>'Scheduled travel'}.fetch(state)
  end

  def warnings
    result=[]
    result << 'Duplicate unfinished journeys' if @duplicate
    result << 'Invalid timing or pause metadata' if invalid?
    ship=travel.user_ship
    expected=travel.is_paused? ? 'interdicted' : 'in_transit'
    result << 'Ship status differs from travel state' if travel.completed_at_tick.nil? && ship.status != expected
    player_name = @player_location_name || ship.shard_user&.current_location_name
    if player_name.present? && ship.location_name != player_name
      result << 'Player location differs from ship location'
    end
    result
  end

  def payload
    paused = state == 'interdicted'
    remaining = paused ? travel.remaining_ticks_from_arrival : [travel.arrival_tick.to_i-tick,0].max
    {travel_state:state,travel_state_label:label,is_paused:travel.is_paused,
     pause_reason:paused ? 'interdiction' : nil,remaining_ticks:remaining,
     arrival_display:paused ? 'No scheduled arrival while interdicted' : label,
     nominal_seconds_after_resume:paused ? [remaining,1].max*Tick.seconds_per_tick : nil,
     warnings:warnings}
  end
end
