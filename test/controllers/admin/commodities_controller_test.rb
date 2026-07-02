require "test_helper"

class Admin::CommoditiesControllerTest < ActionDispatch::IntegrationTest
  test "raw json import redirects with success flash when records import" do
    Admin::Data::CommoditiesImporter.stub :import_raw_json!, 2 do
      post import_raw_json_admin_commodities_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_commodities_path
    assert_equal "Successfully imported 2 commodities.", flash[:notice]
  end

  test "raw json import redirects with alert flash when no records import" do
    Admin::Data::CommoditiesImporter.stub :import_raw_json!, 0 do
      post import_raw_json_admin_commodities_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_commodities_path
    assert_equal "Import failed. Please verify the JSON format.", flash[:alert]
  end

  test "raw json import redirects with alert flash when json is missing" do
    post import_raw_json_admin_commodities_url

    assert_redirected_to admin_commodities_path
    assert_equal "No JSON data was provided.", flash[:alert]
  end

  test "index includes raw json import button and modal" do
    get admin_commodities_url

    assert_response :success
    assert_select "button", text: "Import Commodities JSON"
    assert_select "form[action='#{import_raw_json_admin_commodities_path}'] textarea[name='raw_json']"
    assert_select "p", text: /Existing commodities are updated by api_id/
  end
end
