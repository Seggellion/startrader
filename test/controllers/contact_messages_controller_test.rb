require "test_helper"

class ContactMessagesControllerTest < ActionDispatch::IntegrationTest
  test "valid messages persist without creating a login account" do
    assert_no_difference "User.count" do
      assert_difference "ContactMessage.count", 1 do
        post contact_messages_url, params: { contact_message: payload }, as: :json
      end
    end
    assert_response :success
    assert_equal true, JSON.parse(response.body)["success"]
    assert_equal "visitor@example.test", ContactMessage.order(:id).last.email
  end

  test "invalid messages do not create records" do
    assert_no_difference ["User.count", "ContactMessage.count"] do
      post contact_messages_url, params: { contact_message: payload.merge(email: "invalid") }, as: :json
    end
    assert_response :success
    assert_equal false, JSON.parse(response.body)["success"]
  end

  private

  def payload
    { first_name: "Test", last_name: "Visitor", email: "VISITOR@example.test",
      subject: "Regression test", body: "Local test message" }
  end
end
