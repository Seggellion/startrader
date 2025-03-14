# app/services/planet_position_calculator.rb
class PlanetPositionCalculator
  # Universal Gravitational Constant (G) in MKm^3/kg/s^2
  G = 6.67430e-10
  SCALE = 5 # Scale factor to adjust distances for the game world

  # Lagrange point multipliers for L1 and L2 (approximate relative to planet's orbit)
  L1_MULTIPLIER = 0.01
  L2_MULTIPLIER = 0.01
  
  # Phase shifts for co-orbital stations
  CO_ORBITAL_PHASES = [120, 240, 360]

  def self.calculate_position(location, tick)
    case location.classification
    when 'star'
      calculate_star_position(location, tick)
    when 'planet'
      calculate_planet_position(location, tick)
    when 'moon'
      calculate_moon_position(location, tick)
    when 'space_station'
      calculate_space_station_position(location, tick)
    when 'outpost', 'city'
      if location.id_moon > 0
        calculate_moon_position(location.parent, tick)
      else        
        calculate_planet_position(location.parent, tick)
      end
    else
      
      # fallback or error
      { x: 0.0, y: 0.0 }
    end
  end

  def self.calculate_star_position(location, tick)
    { x: 0.0, y: 0.0 }
  end
  

  def self.calculate_planet_position(location, tick)
  
    planet = location

    semi_major_axis = ((planet.periapsis + planet.apoapsis) / 2.0) / SCALE
    
    mass_central_body = planet.star.mass

    orbital_period = Math.sqrt(4 * Math::PI**2 * semi_major_axis**3 / (G * mass_central_body)).round(10)

    seconds_per_tick = 60
    time_at_perihelion = Time.parse('2024-01-03').to_i
    current_time = time_at_perihelion + (tick * seconds_per_tick)

    mean_anomaly = calculate_mean_anomaly(current_time, time_at_perihelion, orbital_period)
    
    eccentricity = (planet.apoapsis - planet.periapsis) / (planet.apoapsis + planet.periapsis)
    e_anomaly = solve_keplers_equation(eccentricity, mean_anomaly)
    
    true_anomaly = 2 * Math.atan2(Math.sqrt(1 + eccentricity) * Math.sin(e_anomaly / 2), 
                                  Math.sqrt(1 - eccentricity) * Math.cos(e_anomaly / 2))

    distance = semi_major_axis * (1 - eccentricity**2) / (1 + eccentricity * Math.cos(true_anomaly))
    x = distance * Math.cos(true_anomaly)
    y = distance * Math.sin(true_anomaly)

    { x: x, y: y }
  end

 # -----------------------------------------------------
  # 2) Moon orbit around its parent planet
  # -----------------------------------------------------
  def self.calculate_moon_position(location, tick)
    # 2a) Get the parent planet’s position in star coordinates
    parent_planet = location.parent  # e.g. 'Hurston' or 'MicroTech'
    planet_coords = calculate_planet_position(parent_planet, tick)

    # 2b) Calculate the moon’s orbit around that planet
    #     - Use the planet’s mass as the central mass
    #     - Use the moon’s periapsis/apoapsis for the orbit
    semi_major_axis = ((location.periapsis + location.apoapsis) / 2.0) / SCALE
    mass_central_body = parent_planet.mass

    orbital_period = Math.sqrt(
      4 * Math::PI**2 * semi_major_axis**3 / (G * mass_central_body)
    ).round(10)

    # 2c) Convert ticks to time, compute mean anomaly
    seconds_per_tick = 60
    time_at_perihelion = Time.parse('2024-01-03').to_i
    current_time = time_at_perihelion + (tick * seconds_per_tick)
    mean_anomaly = calculate_mean_anomaly(current_time, time_at_perihelion, orbital_period)

    # 2d) Solve for eccentric anomaly using the moon’s eccentricity
    eccentricity = (location.apoapsis - location.periapsis) / (location.apoapsis + location.periapsis)
    e_anomaly = solve_keplers_equation(eccentricity, mean_anomaly)

    # 2e) Get the true anomaly & radial distance
    true_anomaly = 2 * Math.atan2(
      Math.sqrt(1 + eccentricity) * Math.sin(e_anomaly / 2),
      Math.sqrt(1 - eccentricity) * Math.cos(e_anomaly / 2)
    )

    distance = semi_major_axis * (1 - eccentricity**2) / (1 + eccentricity * Math.cos(true_anomaly))

    # 2f) Moon’s position in planet-centric coordinates
    moon_x_local = distance * Math.cos(true_anomaly)
    moon_y_local = distance * Math.sin(true_anomaly)

    # 2g) Offset by the planet’s position to get star-centric coords
    x = planet_coords[:x] + moon_x_local
    y = planet_coords[:y] + moon_y_local

    { x: x, y: y }
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
    return { x: 0.0, y: 0.0 } unless parent_body
  
    parent_position = parent_body.classification == 'moon' ? 
                      calculate_moon_position(parent_body, tick) :
                      calculate_planet_position(parent_body, tick)
  
    phase_index = location.name[-1].to_i - 1
    phase_shift = CO_ORBITAL_PHASES[phase_index] * (Math::PI / 180)
  
    x = parent_position[:x] * Math.cos(phase_shift) - parent_position[:y] * Math.sin(phase_shift)
    y = parent_position[:x] * Math.sin(phase_shift) + parent_position[:y] * Math.cos(phase_shift)
  
    { x: x, y: y }
  end


  def self.calculate_star_gateway_position(location, tick)    
    star = location.parent
    
    # Use assigned periapsis and apoapsis for the Gateway station's semi-major axis
    semi_major_axis = ((location.periapsis + location.apoapsis) / 2.0) / SCALE
  
    # Calculate orbital period using Kepler's Third Law
    
    mass_central_body = star.mass
    orbital_period = Math.sqrt(4 * Math::PI**2 * semi_major_axis**3 / (G * mass_central_body)).round(10)
  
    seconds_per_tick = 60
    time_at_perihelion = Time.parse('2024-01-03').to_i
    current_time = time_at_perihelion + (tick * seconds_per_tick)
  
    mean_anomaly = calculate_mean_anomaly(current_time, time_at_perihelion, orbital_period)
  
    # Phase shift for different Gateway stations
    # Assign phase shifts based on station name
    phase_shift = case location.name
      when /Pyro Gateway/ then 0
      when /Terra Gateway/ then Math::PI / 3
      when /Magnus Gateway/ then 2 * Math::PI / 3
      else 0
    end
  
    x = semi_major_axis * Math.cos(mean_anomaly + phase_shift)
    y = semi_major_axis * Math.sin(mean_anomaly + phase_shift)
  
    { x: x, y: y }
  end
  

  # Mean Anomaly Calculation
  def self.calculate_mean_anomaly(current_time, time_at_perihelion, orbital_period_seconds)
    mean_motion = 2 * Math::PI / orbital_period_seconds
    elapsed_time = current_time - time_at_perihelion
    mean_motion * elapsed_time
  end

  # Kepler's Equation Solver
  def self.solve_keplers_equation(eccentricity, mean_anomaly)
    e_anomaly = mean_anomaly
    delta = 1.0
    while delta > 1e-6
      e_anomaly_new = e_anomaly - (e_anomaly - eccentricity * Math.sin(e_anomaly) - mean_anomaly) / 
                      (1 - eccentricity * Math.cos(e_anomaly))
      delta = (e_anomaly_new - e_anomaly).abs
      e_anomaly = e_anomaly_new
    end
    e_anomaly
  end
end
