require 'minitest/autorun'
require_relative '../lib/orbital/snapshot'

class OrbitalSnapshotTest < Minitest::Test
  def setup
    @rows = [
      row(10, 'Test', 900, 'star_system', nil),
      row(20, 'Inner', 901, 'planet', 'Test'),
      row(30, 'Outer', 902, 'planet', 'Test'),
      row(40, 'Site', 903, 'city', 'Inner')
    ]
    @data = { 'version' => 'synthetic', 'status' => 'approved',
      'units' => { 'distance' => 'Gm', 'mass' => 'kg', 'time' => 'seconds', 'phase' => 'degrees' },
      'clock' => { 'epoch' => '2026-10-23T00:00:00Z', 'origin_tick' => 100,
        'origin_simulation_seconds' => 0, 'simulated_seconds_per_tick' => 3600 },
      'bodies' => @rows.map do |r|
        e = { 'name' => r['name'], 'api_id' => r['api_id'], 'classification' => r['classification'],
          'system' => 'Test', 'parent' => r['parent_name'], 'mass_kg' => 1.98847e30 }
        if r['classification'] == 'planet'
          e.merge!('periapsis_gm' => r['name'] == 'Inner' ? 13 : 20,
            'apoapsis_gm' => r['name'] == 'Inner' ? 13 : 20, 'phase_deg' => 0)
        elsif r['classification'] == 'city'
          e['local_offset_gm'] = { 'x' => 0, 'y' => 0.001, 'z' => 0 }
        end
        e
      end }
  end

  def row(id, name, api_id, classification, parent)
    { 'id' => id, 'name' => name, 'api_id' => api_id, 'classification' => classification,
      'parent_name' => parent, 'star_system_name' => 'Test' }
  end

  def snapshot(tick = 100)
    Orbital::Snapshot.new(rows: @rows, tick: tick, catalog: Orbital::Catalog.new(data: @data))
  end

  def test_one_physical_snapshot_and_parent_composition
    s = snapshot
    assert_in_delta 7, s.distance(20, 30), 1e-9
    assert_in_delta 0.001, s.distance(20, 40), 1e-9
    assert_in_delta 13, s.position(40)[:x], 1e-9
    assert_in_delta 0.001, s.position(40)[:y], 1e-9
    assert_equal 0, s.distance(20, 20)
    assert_equal 'Gm', s.metadata[:distance_unit]
    assert_equal s.distance(30, 20), s.distance(20, 30)
  end

  def test_anchored_clock_and_repeatability
    assert_equal 0, snapshot.elapsed_seconds
    assert_equal 7200, snapshot(102).elapsed_seconds
    assert_equal snapshot(102).position(20), snapshot(102).position(20)
    refute_equal snapshot(102).position(20), snapshot(103).position(20)
    refute_equal snapshot(102).catalog.version,
      Orbital::Catalog.new(data: @data.merge('version' => 'different')).version
  end

  def test_missing_measurement_or_parent_is_explicitly_unavailable
    @rows << row(50, 'Unmeasured', 999, 'moon', 'Inner')
    s = snapshot
    assert_equal false, s.report(50)[:available]
    assert_match(/Unmeasured/, s.report(50)[:unavailable_reason])
    @rows.reject! { |r| r['id'] == 20 }
    assert_raises(Orbital::Unavailable) { snapshot.position(40) }
  end

  def test_cycles_and_duplicate_external_identity_are_rejected
    @rows[1]['parent_name'] = 'Outer'
    @rows[2]['parent_name'] = 'Inner'
    @data['bodies'][1]['parent'] = 'Outer'
    @data['bodies'][2]['parent'] = 'Inner'
    assert_raises(Orbital::Unavailable) { snapshot.position(20) }
    @rows << @rows[1].merge('id' => 99)
    assert_raises(Orbital::Unavailable) { snapshot }
  end

  def test_intersystem_distance_is_rejected_even_if_origins_coincide
    @rows << row(50, 'Other', 999, 'star_system', nil).merge('star_system_name' => 'Other')
    assert_raises(Orbital::Unavailable) { snapshot.distance(10, 50) }
  end

  def test_unknown_city_retains_only_documented_host_center_approximation
    @rows << row(50, 'Town', 999, 'city', 'Inner')
    assert_equal snapshot.position(20), snapshot.position(50)
    @rows << row(60, 'Bad town', 998, 'city', 'Test')
    assert_equal false, snapshot.report(60)[:available]
  end
end
