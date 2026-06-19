require "test_helper"

class Admin::OutpostsControllerTest < ActionDispatch::IntegrationTest
  test "raw json import redirects with success flash when records import" do
    Admin::Data::OutpostsImporter.stub :import_raw_json!, 2 do
      post import_raw_json_admin_outposts_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_outposts_path
    assert_equal "Successfully imported 2 outposts.", flash[:notice]
  end

  test "raw json import redirects with alert flash when no records import" do
    Admin::Data::OutpostsImporter.stub :import_raw_json!, 0 do
      post import_raw_json_admin_outposts_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_outposts_path
    assert_equal "Import failed. Please verify the JSON format.", flash[:alert]
  end
end
