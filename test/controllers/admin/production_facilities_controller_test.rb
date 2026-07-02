require "test_helper"

class Admin::ProductionFacilitiesControllerTest < ActionDispatch::IntegrationTest
  test "raw json import redirects with success flash when records import" do
    Admin::Data::FacilitiesPopulator.stub :import_raw_json!, 2 do
      post import_raw_json_admin_production_facilities_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_production_facilities_path
    assert_equal "Successfully imported 2 facilities.", flash[:notice]
  end

  test "raw json import redirects with alert flash when no records import" do
    Admin::Data::FacilitiesPopulator.stub :import_raw_json!, 0 do
      post import_raw_json_admin_production_facilities_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_production_facilities_path
    assert_equal "Import failed. Please verify the JSON format.", flash[:alert]
  end

  test "raw json import redirects with alert flash when json is missing" do
    post import_raw_json_admin_production_facilities_url

    assert_redirected_to admin_production_facilities_path
    assert_equal "No JSON data was provided.", flash[:alert]
  end
end
