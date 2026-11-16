require "test_helper"
require "minitest/mock"

# M06 — security and legacy-route containment (discovery F-10, F-11, F-23;
# decisions S1-S3).
class SecurityContainmentTest < ActionDispatch::IntegrationTest
  setup do
    Setting.delete_all
    Setting.create!(key: "secret_guid", value: "containment-secret", setting_type: "text")
    @admin = User.create!(username: "ContainAdmin", uid: "contain-admin", twitch_id: "contain-admin",
      provider: "twitch", user_type: "admin")
    @player = User.create!(username: "ContainPlayer", uid: "contain-player", twitch_id: "contain-player",
      provider: "twitch", user_type: "player")
    @old_omniauth = OmniAuth.config.test_mode
  end

  teardown do
    OmniAuth.config.test_mode = @old_omniauth
    OmniAuth.config.mock_auth[:twitch] = nil
  end

  test "tick mutation requires the integration secret (S1, F-10)" do
    calls = 0
    Tick.stub(:increment!, -> { calls += 1 }) do
      post "/api/increment_tick"
      assert_response :unauthorized
      post "/api/increment_tick", params: { secret_guid: "wrong" }
      assert_response :unauthorized
      assert_equal 0, calls, "unauthenticated requests must never advance the simulation"

      post "/api/increment_tick", headers: { "X-Secret-Guid" => "containment-secret" }
      assert_response :success
      assert_equal 1, calls
    end
  end

  test "set_tick is refused clearly instead of crashing (S1, F-10)" do
    post "/api/set_tick", params: { tick: 5 }
    assert_response :unauthorized

    post "/api/set_tick", params: { tick: 5 }, headers: { "X-Secret-Guid" => "containment-secret" }
    assert_response :not_implemented
    assert_match(/not supported/, response.parsed_body["error"])
  end

  test "user JSON routes are admin-only (S2, F-11)" do
    get "/users"
    assert_response :unauthorized
    refute_includes response.body, "contain-player"

    assert_no_difference("User.count") do
      post "/users", params: { user: { username: "Intruder", user_type: "admin" } }
    end
    assert_response :unauthorized

    sign_in(@player, expect: root_path)
    get "/users"
    assert_response :forbidden
    refute_includes response.body, "contain-admin"

    sign_in(@admin, expect: admin_root_path)
    get "/users"
    assert_response :success
    assert_includes response.parsed_body.map { |u| u["uid"] }, "contain-player"
  end

  test "dead minecraft and move routes are gone (S2, S3)" do
    %w[/users/1/edit_minecraft_uuid].each do |path|
      assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path(path, method: :get) }
    end
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/users/1/update_minecraft_uuid", method: :patch)
    end
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/api/user_ships/1/move", method: :post)
    end
    refute defined?(MovesController), "the broken MovesController must not exist"
  end

  test "byebug only loads in development and test (S3, F-23)" do
    dependency = Bundler.definition.dependencies.find { |dep| dep.name == "byebug" }
    assert dependency, "byebug is still available for local debugging"
    assert_equal %i[development test], dependency.groups.sort
  end

  private

  def sign_in(user, expect:)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:twitch] = OmniAuth::AuthHash.new(provider: "twitch", uid: user.uid, info: { name: user.username })
    get "/auth/twitch/callback"
    assert_redirected_to expect
  end
end
