require_relative 'geometry'

module Orbital
  # The global simulation clock is unchanged. Only orbital time is integrated
  # through this immutable, versioned schedule. Each activation inherits the
  # previous segment's phase, including when a later release restores rate 1.
  class Clock
    attr_reader :data, :changes, :step

    def initialize(data)
      @data = data
      @origin = Geometry.number(data.fetch('origin_tick'), 'origin tick')
      @seconds = Geometry.number(data.fetch('origin_simulation_seconds'), 'origin seconds')
      @step = Geometry.number(data.fetch('simulated_seconds_per_tick'), 'clock step')
      raise Unavailable, 'Simulation clock step must be positive' unless step.positive?
      schedule = data.fetch('orbital_progression', [])
      raise Unavailable, 'Orbital progression must be a schedule' unless schedule.is_a?(Array)
      previous = @origin - 1
      @changes = schedule.map do |change|
        raise Unavailable, 'Invalid orbital activation' unless change.is_a?(Hash)
        tick = Geometry.number(change.fetch('activation_tick'), 'activation tick')
        rate = Geometry.number(change.fetch('orbital_progression_multiplier'), 'orbital progression multiplier')
        unless tick == tick.to_i && tick >= @origin && tick > previous && rate.positive?
          raise Unavailable, 'Orbital activations must be ordered integer ticks with positive multipliers'
        end
        previous = tick
        { 'activation_tick' => tick, 'orbital_progression_multiplier' => rate }.freeze
      end.freeze
    rescue KeyError, TypeError
      raise Unavailable, 'Orbital clock is incomplete or invalid'
    end

    def simulation_seconds(tick)
      @seconds + (Geometry.number(tick, 'tick') - @origin) * step
    end

    def metadata(tick)
      tick = Geometry.number(tick, 'tick')
      anchor_tick = @origin
      anchor_seconds = @seconds
      rate = 1.0
      changes.each do |change|
        activation = change.fetch('activation_tick')
        break if tick < activation
        anchor_seconds += (activation - anchor_tick) * step * rate
        anchor_tick = activation
        rate = change.fetch('orbital_progression_multiplier')
      end
      { simulation_seconds: simulation_seconds(tick),
        simulated_seconds_per_tick: step,
        orbital_seconds: anchor_seconds + (tick - anchor_tick) * step * rate,
        orbital_progression_multiplier: rate, orbital_seconds_per_tick: step * rate,
        orbital_activation_anchor: { tick: anchor_tick, orbital_seconds: anchor_seconds }, clock: data }
    end
  end
end
