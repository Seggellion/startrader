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
end
