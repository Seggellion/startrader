require 'minitest/autorun'
require_relative '../lib/orbital/geometry'
require_relative '../lib/orbital/catalog'

# Pure tests deliberately do not boot Rails or touch a database/network.
class OrbitalCoreTest < Minitest::Test
  G = Orbital::Geometry
  MASS = 1.98847e30 # Synthetic fixture, not a production mass decision.

  def point(r, degrees)
    theta = degrees * Math::PI / 180
    { x: r * Math.cos(theta), y: r * Math.sin(theta), z: 0.0 }
  end

  def test_independent_direct_geometry
    [[0, 7], [180, 33], [90, Math.sqrt(569)]].each do |angle, expected|
      assert_in_delta expected, G.distance(point(13, 0), point(20, angle)), 1e-9
    end
    assert_in_delta 95.2, G.distance(point(47.6, 0), point(47.6, 180)), 1e-9
    assert_equal 0, G.distance(point(13, 0), point(13, 0))
    assert_in_delta 8_200_000, G.gm_to_km(8.2), 1e-6
    assert_in_delta 47_600_000, G.gm_to_km(47.6), 1e-6
    assert_equal G.distance(point(13, 0), point(20, 90)), G.distance(point(20, 90), point(13, 0))
  end

  def test_nested_and_z_coordinates
    p = { x: 10, y: 0, z: 0 }
    child = G.add(p, { x: 0, y: 0.001, z: 0 })
    assert_equal({ x: 10.0, y: 0.001, z: 0.0 }, child)
    assert_equal 0.001, G.distance(p, child)
    assert_equal 0.001, G.distance(p, { x: 10, y: 0, z: 0.001 })
  end

  def test_mass_changes_period_but_not_circular_radius
    period = G.period_seconds(13, MASS)
    assert_in_delta 2 * Math::PI * Math.sqrt(2197 / (6.67430e-38 * MASS)), period, 1e-8
    assert_in_delta period / 2, G.period_seconds(13, 4 * MASS), 1e-8
    [MASS, 4 * MASS].each do |mass|
      p = G.position(periapsis_gm: 13, apoapsis_gm: 13, mass_kg: mass, phase_deg: 0, elapsed_seconds: period / 4)
      assert_in_delta 13, G.distance({ x: 0, y: 0, z: 0 }, p), 1e-9
    end
    quarter = G.position(periapsis_gm: 13, apoapsis_gm: 13, mass_kg: MASS, phase_deg: 0, elapsed_seconds: period / 4)
    assert_in_delta 0, quarter[:x], 1e-9
    assert_in_delta 13, quarter[:y], 1e-9
  end

  def test_elliptical_bounds_and_high_eccentricity_convergence
    period = G.period_seconds(50.0005, MASS)
    [0, period / 8, period / 2, -period / 2, period * 9].each do |t|
      p = G.position(periapsis_gm: 0.001, apoapsis_gm: 100, mass_kg: MASS, phase_deg: 0, elapsed_seconds: t)
      r = G.distance({ x: 0, y: 0, z: 0 }, p)
      assert_operator r, :>=, 0.001 - 1e-9
      assert_operator r, :<=, 100 + 1e-9
    end
  end

  def test_unavailable_inputs_are_errors
    [nil, Float::NAN, Float::INFINITY].each { |x| assert_raises(Orbital::Unavailable) { G.number(x, 'test') } }
    assert_raises(Orbital::Unavailable) { G.period_seconds(1, 0) }
    assert_raises(Orbital::Unavailable) { G.distance({ x: 0, y: 0 }, { x: 0, y: 0, z: 0 }) }
  end

  def test_real_catalog_preserves_targets_and_requires_explicit_approval
    c = Orbital::Catalog.new
    assert_equal 14, c.entries.count { |e| e.key?('target_distance_gm') }
    expected = {'Pyro I'=>8.2,'Monox'=>10.6,'Bloom'=>17.8,'Pyro IV'=>47.6,'Pyro V'=>47.6,
      'Terminus'=>68.0,'Nyx I'=>5.0,'Nyx II'=>25.0,'Delamar'=>15.0,'Nyx III'=>48.0,
      'Crusader'=>20.0,'Hurston'=>13.0,'MicroTech'=>42.0,'ArcCorp'=>30.0}
    expected.each do |name, target|
      entry = c.resolve_alias(name)
      assert_equal target, entry['target_distance_gm']
      assert_equal target, entry['periapsis_gm']
      assert_equal target, entry['apoapsis_gm']
    end
    assert_equal 8.2, c.resolve_alias('Pyro 1')['target_distance_gm']
    assert_equal 47.6, c.resolve_alias('P4')['target_distance_gm']
    refute_equal c.resolve_alias('P4')['api_id'], c.resolve_alias('P5')['api_id']
    assert_equal 'Delamar', c.resolve_alias('Levski')['parent']
    assert c.ready!
    pending = Marshal.load(Marshal.dump(c.data))
    pending['status'] = 'pending_product_parameters'
    assert_raises(Orbital::Unavailable) { Orbital::Catalog.new(data: pending).ready! }
    assert_raises(FrozenError) { c.entries.first['mass_kg'] = MASS }
  end

  def test_identity_and_graph_guards
    c = Orbital::Catalog.new
    row = { 'name' => 'Pyro IV', 'api_id' => 243, 'classification' => 'planet', 'star_system_name' => 'Pyro', 'parent_name' => 'Pyro' }
    assert_equal 'Pyro IV', c.entry_for(row)['name']
    assert_nil c.entry_for(row.merge('classification' => 'moon'))
    assert_raises(Orbital::Unavailable) { c.entry_for(row.merge('parent_name' => 'Pyro V')) }
    assert_raises(Orbital::Unavailable) { c.entry_for(row.merge('name' => 'Different body')) }
    assert_raises(Orbital::Unavailable) { c.validate_rows!([row, row], complete: false) }
  end
end
