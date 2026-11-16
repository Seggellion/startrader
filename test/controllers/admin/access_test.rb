require "test_helper"

class Admin::AccessTest < ActionDispatch::IntegrationTest
  test "anonymous imports remain blocked" do
    Admin::Data::TerminalsImporter.stub(:import_raw_json!, ->(*) { flunk "unauthenticated import ran" }) do
      post import_raw_json_admin_terminals_url, params: { raw_json: "[]" }
    end
    assert_redirected_to login_path
  end

  test "players cannot import admin data" do
    identity = SecureRandom.uuid
    sign_in_as(User.create!(username: "player-#{identity}", uid: identity,
                           twitch_id: identity, provider: "twitch", user_type: :player))
    Admin::Data::TerminalsImporter.stub(:import_raw_json!, ->(*) { flunk "non-admin import ran" }) do
      post import_raw_json_admin_terminals_url, params: { raw_json: "[]" }
    end
    assert_redirected_to root_path
  end
end
