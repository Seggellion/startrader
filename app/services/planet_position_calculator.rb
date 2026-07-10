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

    # Simulated seconds since tick 0 (server is authoritative).
    elapsed_sec = simulated_elapsed_seconds(tick)

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

    elapsed_sec = simulated_elapsed_seconds(tick)
    m = wrap2pi(n * (elapsed_sec - T_PERI_EPOCH_SEC))

    e_anom = solve_keplers_equation(e, m)
    nu     = 2 * Math.atan2(Math.sqrt(1 + e) * Math.sin(e_anom / 2), Math.sqrt(1 - e) * Math.cos(e_anom / 2))

    r_mkm   = a_mkm * (1 - e * e) / (1 + e * Math.cos(nu))
    r_scene = r_mkm / UNIT_SCALE

    { x: parent_xy[:x] + r_scene * Math.cos(nu),
      y: parent_xy[:y] + r_scene * Math.sin(nu) }
  end

  # ----- Gateways & co-orbitals: keep outputs in scene units -----
 def self.calculate_space_station_position(location, tick)
    # 1. More robust parent lookup to include stars
    parent_body = location.parent || Location.find_by(name: location.parent_name)

    if location.name.include?('-L1') || location.name.include?('-L2')
      calculate_lagrange_station_position(location, parent_body, tick)
    elsif parent_body && %w[star star_system].include?(parent_body.classification)
      # 2. Route dynamically if the parent is the star
      calculate_star_orbiting_station_position(location, parent_body, tick)
    else      
      calculate_co_orbital_station_position(location, parent_body, tick)
    end
  end

  # Replaces calculate_star_gateway_position
  def self.calculate_star_orbiting_station_position(location, star, tick)
    a_mkm = (location.periapsis + location.apoapsis) / 2.0
    m_c   = star.mass
    t     = period_seconds(a_mkm, m_c)
    n     = 2 * Math::PI / t

    elapsed_sec = simulated_elapsed_seconds(tick)
    m = n * (elapsed_sec - T_PERI_EPOCH_SEC)

    # Find all stations sharing this exact orbit around the same star.
    # Plucking just the ID makes this query lighter and gives us a sortable array.
    shared_orbit_station_ids = Location.where(
      classification: 'space_station',
      parent_name: location.parent_name,
      periapsis: location.periapsis,
      apoapsis: location.apoapsis
    ).order(:id).pluck(:id)

    total_stations = shared_orbit_station_ids.size
    station_index  = shared_orbit_station_ids.index(location.id) || 0

    # Distribute the stations evenly across the 360 degrees (2 * PI radians).
    # e.g., for 3 stations: index 0 gets 0rad, index 1 gets 2.09rad (120deg), index 2 gets 4.18rad (240deg)
    phase_shift = total_stations > 0 ? (2 * Math::PI / total_stations) * station_index : 0.0

    r_scene = (a_mkm / UNIT_SCALE)
    { x: r_scene * Math.cos(m + phase_shift), y: r_scene * Math.sin(m + phase_shift) }
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

  def self.simulated_elapsed_seconds(tick)
    tick.to_f * Tick.simulated_seconds_per_tick
  end
  private_class_method :simulated_elapsed_seconds
end
