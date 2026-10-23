require 'minitest/autorun'
require_relative '../lib/orbital/snapshot'

class OrbitalNestedTest < Minitest::Test
  def setup
    @catalog=Orbital::Catalog.new
    @rows=@catalog.entries.each_with_index.map do |e,i|
      {'id'=>i+1,'name'=>e['name'],'api_id'=>e['api_id'],'classification'=>e['classification'],
        'star_system_name'=>e['system'],'parent_name'=>e['parent']}
    end
  end
  def id(name) = @rows.find { |r| r['name']==name }.fetch('id')
  def state(tick) = Orbital::Snapshot.new(rows:@rows,tick:tick,catalog:@catalog)
  def test_every_moon_and_station_has_finite_distinct_host_relative_geometry
    assert_equal 18,@catalog.entries.count { |e| e['classification']=='moon' }
    assert_equal 60,@catalog.entries.count { |e| e['classification']=='space_station' }
    [0,10,700000].each do |tick|
      s=state(tick)
      @catalog.entries.select { |e| %w[moon space_station].include?(e['classification']) }.each do |e|
        r=s.report(id(e['name']))
        assert r[:available],e['name']
        assert r[:position_gm].values.all?(&:finite?)
        assert_operator r[:local_distance_gm],:>,0
        assert_in_delta e['local_orbit_radius_gm'],r[:local_distance_gm],1e-8 if e['local_orbit_radius_gm']
      end
    end
  end
  def test_independent_moon_and_moon_station_offsets_and_evolving_distance
    s=state(0)
    a=s.position(id('Arial')); h=s.position(id('Hurston'))
    assert_in_delta 0.03*Math.cos(Math::PI/12),a[:x]-h[:x],1e-10
    assert_in_delta 0.03*Math.sin(Math::PI/12),a[:y]-h[:y],1e-10
    y=s.position(id('Yela')); g=s.position(id('Green Imperial Housing Exchange'))
    assert_in_delta 0.001*Math.cos(220*Math::PI/180),g[:x]-y[:x],1e-10
    assert_in_delta 0.001*Math.sin(220*Math::PI/180),g[:y]-y[:y],1e-10
    refute_in_delta s.distance(id('Arial'),id('Aberdeen')),state(1).distance(id('Arial'),id('Aberdeen')),1e-6
  end
  def test_lagrange_inspired_stations_follow_planet_at_all_ticks
    [0,10,700000].each do |tick|
      s=state(tick); host=s.position(id('Hurston'))
      { 'HUR-L1 Green Glade Station'=>[0.98,0], 'HUR-L2 Faithful Dream Station'=>[1.02,0],
        'HUR-L3 Thundering Express Station'=>[1,180], 'HUR-L4 Melodic Fields Station'=>[1,60],
        'HUR-L5 High Course Station'=>[1,-60] }.each do |name,(factor,degrees)|
        angle=degrees*Math::PI/180; p=s.position(id(name))
        assert_in_delta factor*(host[:x]*Math.cos(angle)-host[:y]*Math.sin(angle)),p[:x],1e-9
        assert_in_delta factor*(host[:x]*Math.sin(angle)+host[:y]*Math.cos(angle)),p[:y],1e-9
      end
      assert_in_delta 0.26,s.distance(id('Hurston'),id('HUR-L1 Green Glade Station')),1e-9
      assert_in_delta 13,s.distance(id('Hurston'),id('HUR-L4 Melodic Fields Station')),1e-9
    end
  end
  def test_primary_world_positions_and_clock_are_unchanged_from_v1
    v1=Orbital::Catalog.new(path:File.expand_path('../config/orbital_calibrations/v1.yml',__dir__))
    [0,10,700000].each do |tick|
      old=Orbital::Snapshot.new(rows:@rows,tick:tick,catalog:v1)
      v1.entries.each { |e| assert_equal old.position(id(e['name'])),state(tick).position(id(e['name'])) }
      assert_equal old.metadata[:clock],state(tick).metadata[:clock]
    end
  end
  def test_invalid_coorbital_model_and_host_fail_explicitly
    data=Marshal.load(Marshal.dump(@catalog.data)); data['bodies'].find { |e| e['coorbital'] }['coorbital']['radial_factor']=0
    assert_raises(Orbital::Unavailable) { Orbital::Catalog.new(data:data).ready! }
    @rows.reject! { |r| r['name']=='Hurston' }
    assert_equal false,state(0).report(id('Arial'))[:available]
  end
end
