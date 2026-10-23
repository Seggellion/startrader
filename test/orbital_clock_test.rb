require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require_relative '../lib/orbital/snapshot'

class OrbitalClockTest < Minitest::Test
  def setup
    @old=Orbital::Catalog.new(path:File.expand_path('../config/orbital_calibrations/v2.yml',__dir__))
    @data=Marshal.load(Marshal.dump(@old.data))
    @data['version']='test-rate'
    @data['clock']['orbital_progression']=[{'activation_tick'=>1000,'orbital_progression_multiplier'=>0.01}]
    @catalog=Orbital::Catalog.new(data:@data)
    @rows=@old.entries.each_with_index.map { |e,i| {'id'=>i+1,'name'=>e['name'],'api_id'=>e['api_id'],
      'classification'=>e['classification'],'star_system_name'=>e['system'],'parent_name'=>e['parent']} }
  end
  def snapshot(tick,catalog=@catalog) = Orbital::Snapshot.new(rows:@rows,tick:tick,catalog:catalog)
  def clock(data=@data) = Orbital::Clock.new(data.fetch('clock'))

  def test_unwrapped_angles_and_periods_for_every_kepler_orbit
    @catalog.entries.select { |e| e['periapsis_gm'] }.each do |e|
      mass=@catalog.entries.find { |p| p['system']==e['system'] && p['name']==e['parent'] }.fetch('mass_kg')
      period=Orbital::Geometry.period_seconds((e['periapsis_gm']+e['apoapsis_gm'])/2.0,mass)
      # Unwrapped mean anomaly; atan2 and chord length lose complete turns.
      before=360*(clock.metadata(1000)[:orbital_seconds]-clock.metadata(900)[:orbital_seconds])/period
      after=360*(clock.metadata(1100)[:orbital_seconds]-clock.metadata(1000)[:orbital_seconds])/period
      assert_in_delta 0.01,after/before,1e-12,e['name']
      old_period_ticks=period/clock.metadata(999)[:orbital_seconds_per_tick]
      new_period_ticks=period/clock.metadata(1000)[:orbital_seconds_per_tick]
      assert_in_delta 100,new_period_ticks/old_period_ticks,1e-10,e['name']
    end
  end

  def test_shipping_catalog_preserves_all_v2_body_definitions_and_global_clock
    current=Orbital::Catalog.new
    assert_equal @old.entries,current.entries
    assert_equal @old.data.fetch('clock'),current.data.fetch('clock').reject { |key,_| key=='orbital_progression' }
    assert_equal [0.01],current.data.fetch('clock').fetch('orbital_progression').map { |change| change.fetch('orbital_progression_multiplier') }
  end

  def test_exact_continuity_history_and_unchanged_bodies_radii_and_units
    assert_equal @old.entries,@catalog.entries
    [0,999,1000].each do |tick|
      @rows.each { |r| assert_equal snapshot(tick,@old).position(r['id']),snapshot(tick).position(r['id']) }
    end
    @rows.each do |r|
      report=snapshot(1010).report(r['id'])
      old_report=snapshot(1010,@old).report(r['id'])
      assert_in_delta old_report[:local_distance_gm],report[:local_distance_gm],1e-8 if report[:local_distance_gm]
      assert_equal 'Gm',report[:distance_unit]
    end
    assert_equal 604800*1010,snapshot(1010).elapsed_seconds
    assert_equal 604800*1000+6048*10,snapshot(1010).orbital_seconds
    assert_in_delta 8_200_000,Orbital::Geometry.gm_to_km(8.2),1e-6
    assert_equal 0.01,snapshot(1010).metadata[:orbital_progression_multiplier]
    @rows.each { |r| assert_equal snapshot(1001,@old).position(r['id']),snapshot(1100).position(r['id']) }
  end

  def test_restart_reload_pause_and_version_retain_identical_phase_anchor
    Dir.mktmpdir do |dir|
      path=File.join(dir,'catalog.yml'); File.write(path,YAML.dump(@data))
      reloaded=Orbital::Catalog.new(path:path)
      [999,1000,1010,1_000_000].each do |tick|
        assert_equal @catalog.version,reloaded.version
        assert_equal snapshot(tick).metadata,snapshot(tick,reloaded).metadata
        @rows.each { |r| assert_equal snapshot(tick).position(r['id']),snapshot(tick,reloaded).position(r['id']) }
      end
    end
  end

  def test_phase_safe_reversal_appends_history_and_restores_rate_without_jump
    @data['clock']['orbital_progression'] << {'activation_tick'=>2000,'orbital_progression_multiplier'=>1.0}
    restored=Orbital::Catalog.new(data:@data)
    [999,1000,1500,2000].each do |tick|
      @rows.each { |r| assert_equal snapshot(tick).position(r['id']),snapshot(tick,restored).position(r['id']) }
    end
    assert_equal 604800, snapshot(2001,restored).orbital_seconds-snapshot(2000,restored).orbital_seconds
    assert_equal 6048, snapshot(2000).orbital_seconds-snapshot(1999).orbital_seconds
    assert_equal 1.0,snapshot(2000,restored).metadata[:orbital_progression_multiplier]
    refute_equal @catalog.version,restored.version
  end

  def test_chord_length_is_not_used_as_angular_rate_ratio
    period=Orbital::Geometry.period_seconds(13,1.98847e30)
    old_angle=2*Math::PI*604800/period
    refute_in_delta 0.01,Math.sin(old_angle*0.01/2).abs/Math.sin(old_angle/2).abs,1e-4
  end

  def test_invalid_and_reordered_schedules_fail_closed
    [nil,{},[{}],[{'activation_tick'=>1000,'orbital_progression_multiplier'=>0}],
      [{'activation_tick'=>1.5,'orbital_progression_multiplier'=>0.01}],
      [{'activation_tick'=>1000,'orbital_progression_multiplier'=>0.01},{'activation_tick'=>999,'orbital_progression_multiplier'=>1}],
      [{'activation_tick'=>1000,'orbital_progression_multiplier'=>Float::INFINITY}]].each do |schedule|
      data=Marshal.load(Marshal.dump(@data)); data['clock']['orbital_progression']=schedule
      assert_raises(Orbital::Unavailable) { Orbital::Catalog.new(data:data).ready! }
    end
  end

  def test_release_generator_preserves_history_and_refuses_overwrite_or_retroactive_activation
    Dir.mktmpdir do |dir|
      source=File.join(dir,'source.yml'); output=File.join(dir,'next.yml'); File.write(source,YAML.dump(@data))
      args=['--source',source,'--output',output,'--version','next','--current-tick','1500','--activation-tick','2000','--multiplier','1']
      script=File.expand_path('../script/orbital_progression.rb',__dir__)
      _,error,status=Open3.capture3(RbConfig.ruby,script,*args)
      assert status.success?,error
      generated=Orbital::Catalog.new(path:output)
      assert_equal @catalog.entries,generated.entries
      assert_equal @catalog.data['clock']['orbital_progression'],generated.data['clock']['orbital_progression'][0...-1]
      assert_equal snapshot(2000).position(4),snapshot(2000,generated).position(4)
      _,_,status=Open3.capture3(RbConfig.ruby,script,*args)
      refute status.success?
      args[args.index('--activation-tick')+1]='1400'
      _,_,status=Open3.capture3(RbConfig.ruby,script,*args)
      refute status.success?
    end
  end
end
