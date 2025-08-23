# app/services/planet_position_calculator.rb
class PlanetPositionCalculator
  # G in Mkm^3 / kg / s^2 (matches JS)
  G = 6.67430e-38

  L1_MULTIPLIER = 0.01
  L2_MULTIPLIER = 0.01

  # Must match CelestialBody.SCALE_POS in JS
  UNIT_SCALE = 5.0

  # Same epoch JS uses to anchor phase
  T_PERI_EPOCH_SEC = Time.utc(2024, 1, 3, 0, 0, 0).to_i

  def self.wrap2pi(x)
    x %= (2 * Math::PI)
    x += 2 * Math::PI if x < 0
    x
  end

 def self.calculate_position(location, tick)
    case location.classification
    when 'star_system', 'star'
      # Star is at origin in scene coordinates
      { x: 0.0, y: 0.0 }
    when 'planet'
      calculate_planet_position(location, tick)
    when 'moon'
      calculate_moon_position(location, tick)
    when 'space_station'
      calculate_space_station_position(location, tick)
    when 'outpost', 'city'
      # Cities/outposts sit with their parent (planet or moon)
      parent = location.parent
      return { x: 0.0, y: 0.0 } unless parent

      if parent.classification == 'moon'
        calculate_moon_position(parent, tick)
      else
        calculate_planet_position(parent, tick)
      end
    else
      { x: 0.0, y: 0.0 }
    end
  end

  def self.period_seconds(a_mkm, mass_kg)
    mu = G * mass_kg
    2 * Math::PI * Math.sqrt((a_mkm ** 3) / mu)
  end

  # ----- PLANETS (physics in real units; scale only at the end) -----
  def self.calculate_planet_position(location, tick)
    planet = location

    a_mkm = (planet.periapsis + planet.apoapsis) / 2.0                      # REAL units (Mkm)
    e     = (planet.apoapsis - planet.periapsis) / (planet.apoapsis + planet.periapsis)
    m_c   = planet.star.mass                                                # kg

    t     = period_seconds(a_mkm, m_c)
    n     = 2 * Math::PI / t                                                # rad/s

    # seconds simulated since tick 0 (server is authoritative)
    elapsed_sec = tick * Tick::SIMULATED_HOURS_PER_TICK

    # JS-equivalent mean anomaly: M = n * (elapsed_sec - T_PERI_EPOCH_SEC)
    m = wrap2pi(n * (elapsed_sec - T_PERI_EPOCH_SEC))

    e_anom = solve_keplers_equation(e, m)
    nu     = 2 * Math.atan2(Math.sqrt(1 + e) * Math.sin(e_anom / 2), Math.sqrt(1 - e) * Math.cos(e_anom / 2))

    r_mkm  = a_mkm * (1 - e * e) / (1 + e * Math.cos(nu))                   # REAL radius (Mkm)
    r_scene = r_mkm / UNIT_SCALE                                            # scale for game world

    { x: r_scene * Math.cos(nu), y: r_scene * Math.sin(nu) }
  end

  # ----- MOONS (same pattern as planets) -----
  def self.calculate_moon_position(location, tick)
    parent = location.parent
    parent_xy = calculate_planet_position(parent, tick)                      # already in scene units

    a_mkm = (location.periapsis + location.apoapsis) / 2.0
    e     = (location.apoapsis - location.periapsis) / (location.apoapsis + location.periapsis)
    m_c   = parent.mass

    t     = period_seconds(a_mkm, m_c)
    n     = 2 * Math::PI / t

    elapsed_sec = tick * Tick::SIMULATED_HOURS_PER_TICK
    m = wrap2pi(n * (elapsed_sec - T_PERI_EPOCH_SEC))

    e_anom = solve_keplers_equation(e, m)
    nu     = 2 * Math.atan2(Math.sqrt(1 + e) * Math.sin(e_anom / 2), Math.sqrt(1 - e) * Math.cos(e_anom / 2))

    r_mkm   = a_mkm * (1 - e * e) / (1 + e * Math.cos(nu))
    r_scene = r_mkm / UNIT_SCALE

    { x: parent_xy[:x] + r_scene * Math.cos(nu),
      y: parent_xy[:y] + r_scene * Math.sin(nu) }
  end

  # ----- Gateways & co-orbitals: keep outputs in scene units -----
  def self.calculate_star_gateway_position(location, tick)
    star = location.parent
    a_mkm = (location.periapsis + location.apoapsis) / 2.0                  # REAL
    m_c   = star.mass
    t     = period_seconds(a_mkm, m_c)
    n     = 2 * Math::PI / t

    elapsed_sec = tick * Tick::SIMULATED_HOURS_PER_TICK
    m = n * (elapsed_sec - T_PERI_EPOCH_SEC)

    phase_shift = case location.name
                  when /Pyro Gateway/   then 0.0
                  when /Terra Gateway/  then Math::PI / 3
                  when /Magnus Gateway/ then 2 * Math::PI / 3
                  else 0.0
                  end

    r_scene = (a_mkm / UNIT_SCALE)
    { x: r_scene * Math.cos(m + phase_shift), y: r_scene * Math.sin(m + phase_shift) }
  end


def self.calculate_space_station_position(location, tick)
    parent_body = Location.planets.find_by(name: location.parent_name) || Location.moons.find_by(name: location.parent_name)
  
    if location.name.include?('-L1') || location.name.include?('-L2')
      calculate_lagrange_station_position(location, parent_body, tick)
    elsif location.name.include?('Gateway')
      calculate_star_gateway_position(location, tick)
    else      
      calculate_co_orbital_station_position(location, parent_body, tick)
    end
  end

  def self.calculate_lagrange_station_position(location, parent_body, tick)
    return { x: 0.0, y: 0.0 } unless parent_body
  
    parent_position = parent_body.classification == 'moon' ? 
                      calculate_moon_position(parent_body, tick) :
                      calculate_planet_position(parent_body, tick)
  
    lagrange_multiplier = location.name.include?('-L1') ? L1_MULTIPLIER : -L2_MULTIPLIER
  
    x = parent_position[:x] + (lagrange_multiplier * parent_position[:x])
    y = parent_position[:y] + (lagrange_multiplier * parent_position[:y])
  
    { x: x, y: y }
  end

  def self.calculate_co_orbital_station_position(location, parent_body, tick)
    parent_xy = parent_body.classification == 'moon' ? calculate_moon_position(parent_body, tick)
                                                     : calculate_planet_position(parent_body, tick)

    phase_index = location.name[-1].to_i - 1
    phase_shift = [120, 240, 360][phase_index] * (Math::PI / 180.0)

    x = parent_xy[:x] * Math.cos(phase_shift) - parent_xy[:y] * Math.sin(phase_shift)
    y = parent_xy[:x] * Math.sin(phase_shift) + parent_xy[:y] * Math.cos(phase_shift)
    { x: x, y: y }
  end

  # Kepler solver unchanged, but keep tolerance identical to JS (1e-6)
  def self.solve_keplers_equation(e, m)
    e_anom = m
    delta = 1.0
    while delta > 1e-6
      enew = e_anom - (e_anom - e * Math.sin(e_anom) - m) / (1 - e * Math.cos(e_anom))
      delta = (enew - e_anom).abs
      e_anom = enew
    end
    e_anom
  end
end
