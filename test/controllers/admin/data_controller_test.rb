require "test_helper"

class Admin::DataControllerTest < ActionDispatch::IntegrationTest
  test "star systems raw json import redirects with success flash when records import" do
    Admin::Data::StarSystemsImporter.stub :import_raw_json!, 2 do
      post import_star_systems_admin_data_url, params: { json_data: "[]" }
    end

    assert_redirected_to admin_star_systems_path
    assert_equal "Successfully imported 2 star systems.", flash[:notice]
  end

  test "star systems raw json import redirects with alert flash when no records import" do
    Admin::Data::StarSystemsImporter.stub :import_raw_json!, 0 do
      post import_star_systems_admin_data_url, params: { json_data: "[]" }
    end

    assert_redirected_to admin_star_systems_path
    assert_equal "Import failed. Please verify the JSON format.", flash[:alert]
  end

  test "star systems raw json import redirects with alert flash when json is missing" do
    post import_star_systems_admin_data_url

    assert_redirected_to admin_star_systems_path
    assert_equal "No JSON data was provided.", flash[:alert]
  end

  test "facilities api import redirects with success flash when records import" do
    Admin::Data::FacilitiesPopulator.stub :import_all!, 3 do
      post populate_facilities_admin_data_url
    end

    assert_redirected_to admin_production_facilities_path
    assert_equal "Successfully imported 3 facilities.", flash[:notice]
  end

  test "facilities api import redirects with alert flash when no records import" do
    Admin::Data::FacilitiesPopulator.stub :import_all!, 0 do
      post populate_facilities_admin_data_url
    end

    assert_redirected_to admin_production_facilities_path
    assert_equal "Failed to import facilities.", flash[:alert]
  end

  test "commodities api import redirects with success flash when records import" do
    Admin::Data::CommoditiesImporter.stub :import_all!, 5 do
      post import_commodities_admin_data_url
    end

    assert_redirected_to admin_commodities_path
    assert_equal "Successfully imported 5 commodities.", flash[:notice]
  end

  test "commodities api import redirects with alert flash when no records import" do
    Admin::Data::CommoditiesImporter.stub :import_all!, 0 do
      post import_commodities_admin_data_url
    end

    assert_redirected_to admin_commodities_path
    assert_equal "Failed to import commodities.", flash[:alert]
  end

  test "terminals api import redirects with success flash when records import" do
    Admin::Data::TerminalsImporter.stub :import_all!, 4 do
      post import_terminals_admin_data_url
    end

    assert_redirected_to admin_terminals_path
    assert_equal "Successfully imported 4 terminals.", flash[:notice]
  end

  test "terminals api import redirects with alert flash when no records import" do
    Admin::Data::TerminalsImporter.stub :import_all!, 0 do
      post import_terminals_admin_data_url
    end

    assert_redirected_to admin_terminals_path
    assert_equal "Failed to import terminals.", flash[:alert]
  end
end
