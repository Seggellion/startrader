require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_admin }

  test "index renders the admin dashboard" do
    get admin_root_url
    assert_response :success
  end
end
