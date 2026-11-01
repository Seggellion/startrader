# Pure row-local contract, usable without booting Rails against production.
module TravelStateContract
  def self.valid_pause?(row)
    r=row.transform_keys(&:to_s)
    r['is_paused']==true && r['completed_at_tick'].nil? &&
      r['departure_tick'].is_a?(Integer) && r['departure_tick']>=0 &&
      r['paused_at_tick'].is_a?(Integer) && r['paused_at_tick']>=r['departure_tick'] &&
      r['remaining_ticks_from_arrival'].is_a?(Integer) && r['remaining_ticks_from_arrival']>=0 &&
      r['interdiction_count'].to_i>0 && r['last_interdicted_tick']==r['paused_at_tick']
  end
  def self.invalid?(row)
    r=row.transform_keys(&:to_s)
    !r['arrival_tick'].is_a?(Integer) || r['arrival_tick']<0 ||
      !r['departure_tick'].is_a?(Integer) || r['departure_tick']<0 ||
      (r['arrival_tick']==0 && !valid_pause?(r)) ||
      (r['is_paused']==true && !valid_pause?(r))
  end
  def self.state(row,tick)
    r=row.transform_keys(&:to_s)
    return 'invalid' if invalid?(r)
    return 'completed' if r['completed_at_tick']
    return 'interdicted' if r['is_paused']
    r['arrival_tick']<=tick ? 'awaiting_completion' : 'scheduled'
  end
end
