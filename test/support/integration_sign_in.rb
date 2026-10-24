# Exercise the real OAuth callback/session, without external authentication or avatars.
module IntegrationSignIn
  def sign_in_as(user)
    previous_test_mode = OmniAuth.config.test_mode
    previous_auth = OmniAuth.config.mock_auth[:twitch]
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:twitch] = OmniAuth::AuthHash.new(
      provider: "twitch", uid: user.uid, info: { name: user.username }
    )
    get "/auth/twitch/callback"
    assert_redirected_to(user.admin? ? admin_root_path : root_path)
  ensure
    OmniAuth.config.mock_auth[:twitch] = previous_auth
    OmniAuth.config.test_mode = previous_test_mode
  end

  def sign_in_admin
    identity = SecureRandom.uuid
    sign_in_as(User.create!(username: "admin-#{identity}", uid: identity,
                           twitch_id: identity, provider: "twitch", user_type: :admin))
  end
end

ActionDispatch::IntegrationTest.include IntegrationSignIn
