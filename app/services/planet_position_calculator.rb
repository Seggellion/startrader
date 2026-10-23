# Coordinates returned by this compatibility entry point are physical Gm.
class PlanetPositionCalculator
  G = Orbital::Geometry::G
  def self.calculate_position(location, tick)
    OrbitalState.snapshot(tick: tick, systems: [location.star_system_name]).position(location.id)
  end
  def self.period_seconds(axis_gm, mass_kg)
    Orbital::Geometry.period_seconds(axis_gm, mass_kg)
  end
end
