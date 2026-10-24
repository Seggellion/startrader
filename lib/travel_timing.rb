module TravelTiming
  # Ordinary travel uses physical Gm/tick. Imported Ship#speed is legacy
  # reference data; neither it nor orbital simulation seconds is a conversion.
  SPEED_GM_PER_TICK = 1.0
  MINIMUM_DURATION_TICKS = 2

  def self.duration_ticks(distance_gm)
    unless distance_gm.is_a?(Numeric) && distance_gm.finite? && distance_gm >= 0
      raise ArgumentError, 'Travel distance must be finite, nonnegative physical Gm'
    end
    [(distance_gm / SPEED_GM_PER_TICK).ceil, MINIMUM_DURATION_TICKS].max
  end

  def self.metadata(duration_ticks:, seconds_per_tick:)
    { travel_speed_gm_per_tick: SPEED_GM_PER_TICK,
      travel_duration_ticks: duration_ticks, seconds_per_tick: seconds_per_tick,
      nominal_travel_seconds: duration_ticks * seconds_per_tick }
  end
end
