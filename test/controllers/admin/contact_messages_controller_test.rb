require "test_helper"

class Admin::ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_admin }

  test "index renders contact messages" do
    get admin_contact_messages_url
    assert_response :success
  end

  test "show marks an unread message read" do
    message = contact_messages(:one)
    message.update!(read_at: nil)
    get admin_contact_message_url(message)
    assert_response :success
    assert_not_nil message.reload.read_at
  end
end
