require 'test_helper'
require_relative '../../lib/orbital/catalog'

class OrbitalCatalogTest < ActiveSupport::TestCase
  setup do
    @star = Location.create!(name: 'Stanton', api_id: 68, classification: 'star_system', star_system_name: 'Stanton')
    @planet = Location.create!(name: 'Hurston', api_id: 116, classification: 'planet',
      star_system_name: 'Stanton', parent_name: 'Stanton', periapsis: 13, apoapsis: 13)
  end

  test 'actual planet import cannot alter the effective catalog distance' do
    assert Admin::Data::PlanetsImporter.import_location(
      'id' => 116, 'name' => 'Hurston', 'star_system_name' => 'Stanton', 'id_star_system' => 68)
    @planet.reload
    assert_equal 147, @planet.periapsis # The real legacy writer was exercised.
    catalog = Orbital::Catalog.new
    assert_equal 13, catalog.entry_for(@planet.attributes)['target_distance_gm']
    assert catalog.ready!
  end

  test 'moon and station reimports preserve calibrated local geometry and mass' do
    moon=Location.create!(name:'Arial',api_id:4,classification:'moon',star_system_name:'Stanton',parent_name:'Hurston')
    assert Admin::Data::MoonsImporter.import_location('id'=>4,'name'=>'Arial','planet_name'=>'Hurston','star_system_name'=>'Stanton','id_star_system'=>68)
    assert_equal 70,moon.reload.periapsis
    assert_equal 0.03,OrbitalState.effective_attributes(moon)[:periapsis]
    assert_equal 7.35e22,OrbitalState.effective_attributes(moon)[:mass]
    station=Location.create!(name:'Everus Harbor',api_id:10,classification:'space_station',star_system_name:'Stanton',parent_name:'Hurston')
    assert Admin::Data::StationsImporter.import_location('id'=>10,'name'=>'Everus Harbor','moon_name'=>'','planet_name'=>'Hurston','star_system_name'=>'Stanton','id_star_system'=>68)
    assert_equal 'Hurston',station.reload.parent_name
    assert_equal 0.0014,OrbitalState.effective_attributes(station)[:periapsis]
    assert_not station.update(parent_name:'Crusader')
  end

  test 'explicit synthetic catalog mass survives the actual star system importer' do
    data = YAML.safe_load_file(Orbital::Catalog::DEFAULT_PATH)
    data['bodies'].find { |e| e['name'] == 'Stanton' }['mass_kg'] = 2.0e30
    catalog = Orbital::Catalog.new(data: data)
    assert Admin::Data::StarSystemsImporter.import_location(
      'id' => 68, 'name' => 'Stanton', 'star_system_name' => 'Stanton', 'code' => 'ST')
    @star.reload
    assert_equal 166_500_000, @star.mass
    assert_equal 2.0e30, catalog.entry_for(@star.attributes)['mass_kg']
  end

  test 'raw admin field edits cannot change the effective target and identity drift fails closed' do
    @planet.update!(periapsis: 999, apoapsis: nil, mass: 5)
    catalog = Orbital::Catalog.new
    assert_equal 13, catalog.entry_for(@planet.reload.attributes)['target_distance_gm']
    assert_not @planet.update(parent_name: 'Pyro')
    @planet.update_columns(parent_name: 'Pyro') # Even a validation bypass fails at the resolver.
    assert_raises(Orbital::Unavailable) { catalog.entry_for(@planet.reload.attributes) }
  end

  test 'read-only fixture checker detects a real invalid relationship' do
    connection = ActiveRecord::Base.connection
    connection.execute('CREATE TABLE orbital_fk_parent (id integer PRIMARY KEY)')
    connection.execute('CREATE TABLE orbital_fk_child (parent_id integer)')
    connection.execute('INSERT INTO orbital_fk_child VALUES (99)')
    connection.execute('ALTER TABLE orbital_fk_child ADD CONSTRAINT orbital_fixture_fk FOREIGN KEY (parent_id) REFERENCES orbital_fk_parent(id) NOT VALID')
    # DDL is transactional in this isolated test DB; scope the inventory.
    connection.stub(:tables, ['orbital_fk_child']) do
      assert_raises(ActiveRecord::InvalidForeignKey) { connection.check_all_foreign_keys_valid! }
    end
  ensure
    connection&.execute('DROP TABLE IF EXISTS orbital_fk_child')
    connection&.execute('DROP TABLE IF EXISTS orbital_fk_parent')
  end

  test 'generic importer scopes overlapping external IDs and retains name-based parents' do
    Location.create!(name: 'Overlapping Station', api_id: 116, classification: 'space_station', star_system_name: 'Stanton')
    assert Admin::Data::LocationsImporter.import_location('id'=>116, 'type'=>'planet', 'name'=>'Hurston',
      'id_star_system'=>68, 'star_system_name'=>'Stanton', 'periapsis'=>nil, 'apoapsis'=>nil)
    assert_equal 'Stanton', @planet.reload.parent_name
    assert_equal 'space_station', Location.find_by!(name: 'Overlapping Station').classification
    assert_equal 13, OrbitalState.effective_attributes(@planet)[:periapsis]
  end

  test 'city reimports preserve Levski effective Delamar inheritance despite nil orbital inputs' do
    Location.create!(name: 'Nyx', api_id: 55, classification: 'star_system', star_system_name: 'Nyx')
    Location.create!(name: 'Delamar', api_id: 325, classification: 'planet', star_system_name: 'Nyx', parent_name: 'Nyx')
    city = Location.create!(name: 'Levski', api_id: 2, classification: 'city', star_system_name: 'Nyx', parent_name: 'Delamar')
    payload = {'id'=>2, 'type'=>'city', 'name'=>'Levski', 'id_city'=>2, 'id_planet'=>325,
      'id_star_system'=>55, 'star_system_name'=>'Nyx', 'planet_name'=>'Delamar', 'periapsis'=>nil, 'apoapsis'=>nil}
    assert Admin::Data::CitiesImporter.import_location(payload)
    assert Admin::Data::LocationsImporter.import_location(payload)
    assert_equal 'Delamar', city.reload.parent_name
    assert_equal 'Delamar', OrbitalState.effective_attributes(city)[:parent]
  end
end
