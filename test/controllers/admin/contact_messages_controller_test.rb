require "test_helper"

class Admin::ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get admin_contact_messages_index_url
    assert_response :success
  end

  test "should get show" do
    get admin_contact_messages_show_url
    assert_response :success
  end
end
