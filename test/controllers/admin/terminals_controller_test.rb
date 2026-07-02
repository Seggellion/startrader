require "test_helper"

class Admin::TerminalsControllerTest < ActionDispatch::IntegrationTest
  test "raw json import redirects with success flash when records import" do
    Admin::Data::TerminalsImporter.stub :import_raw_json!, 2 do
      post import_raw_json_admin_terminals_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_terminals_path
    assert_equal "Successfully imported 2 terminals.", flash[:notice]
  end

  test "raw json import success flash includes import summary when available" do
    result = Admin::Data::TerminalsImporter::ImportResult.new(
      total: 4,
      imported: 3,
      skipped: 1,
      failed: 0
    )

    Admin::Data::TerminalsImporter.stub :import_raw_json!, result do
      post import_raw_json_admin_terminals_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_terminals_path
    assert_equal "Imported 3 terminals. Skipped 1. Failed 0.", flash[:notice]
  end

  test "raw json import redirects with alert flash when no records import" do
    Admin::Data::TerminalsImporter.stub :import_raw_json!, 0 do
      post import_raw_json_admin_terminals_url, params: { raw_json: "[]" }
    end

    assert_redirected_to admin_terminals_path
    assert_equal "Import failed. Please verify the JSON format.", flash[:alert]
  end

  test "raw json import redirects with alert flash when json is missing" do
    post import_raw_json_admin_terminals_url

    assert_redirected_to admin_terminals_path
    assert_equal "No JSON data was provided.", flash[:alert]
  end

  test "index includes raw json import button and modal" do
    get admin_terminals_url

    assert_response :success
    assert_select "button", text: "Import Terminals JSON"
    assert_select "form[action='#{import_raw_json_admin_terminals_path}'] textarea[name='raw_json']"
    assert_select "p", text: /old UEX terminals API source is deprecated/
  end
end
