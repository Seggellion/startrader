require_relative 'unavailable'

module Orbital

  # Physical units only: Gm, kg, seconds. No renderer or database dependency.
  module Geometry
    G = 6.67430e-38
    TAU = 2.0 * Math::PI
    module_function

    def number(value, label)
      n = Float(value)
      raise Unavailable, "#{label} must be finite" unless n.finite?
      n
    rescue ArgumentError, TypeError
      raise Unavailable, "#{label} is unavailable"
    end

    def period_seconds(axis_gm, mass_kg)
      a = number(axis_gm, 'semimajor axis Gm')
      mass = number(mass_kg, 'central mass kg')
      raise Unavailable, 'Axis and central mass must be positive' unless a.positive? && mass.positive?
      number(TAU * Math.sqrt(a**3 / (G * mass)), 'period seconds')
    end

    # Phase is mean anomaly at the explicit simulation epoch, in degrees.
    def position(periapsis_gm:, apoapsis_gm:, mass_kg:, phase_deg:, elapsed_seconds:)
      q = number(periapsis_gm, 'periapsis Gm')
      big_q = number(apoapsis_gm, 'apoapsis Gm')
      raise Unavailable, 'Require 0 < periapsis <= apoapsis' unless q.positive? && big_q >= q
      a = (q + big_q) / 2.0
      e = (big_q - q) / (big_q + q)
      raise Unavailable, 'Eccentricity is outside the supported precision' unless e >= 0 && e < 1
      period = period_seconds(a, mass_kg)
      phase = number(phase_deg, 'epoch phase degrees') * Math::PI / 180.0
      elapsed = number(elapsed_seconds, 'elapsed simulation seconds')
      mean = (phase + TAU * ((elapsed % period) / period)) % TAU
      eccentric = eccentric_anomaly(e, mean)
      { x: a * (Math.cos(eccentric) - e),
        y: a * Math.sqrt(1.0 - e * e) * Math.sin(eccentric), z: 0.0 }
    end

    def eccentric_anomaly(e, mean)
      # Monotonic equation on [0,2*pi]; bounded even near e=1.
      lower = 0.0
      upper = TAU
      64.times do
        mid = (lower + upper) / 2.0
        residual = mid - e * Math.sin(mid) - mean
        residual.positive? ? upper = mid : lower = mid
      end
      (lower + upper) / 2.0
    end

    def distance(a, b)
      number(Math.sqrt(%i[x y z].sum do |axis|
        (number(b.fetch(axis), axis) - number(a.fetch(axis), axis))**2
      end), 'distance Gm')
    rescue KeyError
      raise Unavailable, 'XYZ coordinates are required'
    end

    def add(parent, local)
      %i[x y z].to_h { |axis| [axis, number(parent.fetch(axis), axis) + number(local.fetch(axis), axis)] }
    end

    def gm_to_km(value) = number(value, 'distance Gm') * 1_000_000.0
  end
end
