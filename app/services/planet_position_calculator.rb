# app/services/planet_position_calculator.rb
class PlanetPositionCalculator
    # Universal Gravitational Constant (G) in MKm^3/kg/s^2
    G = 6.67430e-10
    SCALE = 5 # Scale factor to adjust distances for the game world
  
    def self.calculate_position(location, tick)
      # Calculate semi-major axis in MKm
      
      
      planet = Location.planets.find_by(api_id: location.id_planet) || Location.planets.find_by(api_id: location.api_id)
   
      semi_major_axis = ((planet.periapsis + planet.apoapsis) / 2.0) / SCALE
      
      # Assuming mass is in kg and represents the mass of the central body (e.g., a star)
      
      mass_central_body = planet.star.mass
  
      # Calculate orbital period using Kepler's Third Law
      orbital_period = Math.sqrt(4 * Math::PI**2 * semi_major_axis**3 / (G * mass_central_body)).round(10)
      
      # Calculate mean anomaly using ticks instead of timestamps
      # Assuming 1 tick = 1 minute (or customize as needed)
      seconds_per_tick = 60
      time_at_perihelion = Time.parse('2024-01-03').to_i
      current_time = time_at_perihelion + (tick * seconds_per_tick)
      
      mean_anomaly = calculate_mean_anomaly(current_time, time_at_perihelion, orbital_period)
      
      # Solve Kepler's Equation for Eccentric Anomaly (E)
      eccentricity = (planet.apoapsis - planet.periapsis) / (planet.apoapsis + planet.periapsis)
      e_anomaly = solve_keplers_equation(eccentricity, mean_anomaly)
      
      # Calculate True Anomaly (ν) from Eccentric Anomaly (E)
      true_anomaly = 2 * Math.atan2(Math.sqrt(1 + eccentricity) * Math.sin(e_anomaly / 2), 
                                    Math.sqrt(1 - eccentricity) * Math.cos(e_anomaly / 2))
  
      # Convert True Anomaly to position in orbit
      distance = semi_major_axis * (1 - eccentricity**2) / (1 + eccentricity * Math.cos(true_anomaly))
      x = distance * Math.cos(true_anomaly)
      y = distance * Math.sin(true_anomaly)
      
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
  