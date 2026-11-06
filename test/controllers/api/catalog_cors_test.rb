require "test_helper"

class Api::CatalogCorsTest < ActionDispatch::IntegrationTest
  MAIDENBOT_WWW = "https://www.maidenbot.com"
  EXISTING_ORIGINS = [
    "https://maidenbot.com",
    "https://starbitizen.com",
    "https://www.starbitizen.com"
  ].freeze
  CATALOG_PATHS = ["/api/ships", "/api/locations", "/api/commodities"].freeze

  setup do
    @ship = Ship.create!(
      model: "CORS Catalog Ship", slug: "cors-catalog-ship", name: "Catalog Ship",
      company_name: "Drake Interplanetary", is_spaceship: true, is_ground_vehicle: false,
      scu: 100, is_docking: true, ship_image_primary: "/catalog/ship.png",
      length: 111, msrp: 295, fuel_quantum: 2500, hp: 80
    )
    Ship.create!(model: "CORS Ground Vehicle", is_spaceship: true, is_ground_vehicle: true)
    Ship.create!(model: "CORS Nonspaceship", is_spaceship: false, is_ground_vehicle: false)
  end

  test "www maidenbot reads the anonymous legacy ship catalog with one exact grant" do
    get "/api/ships", headers: { "Origin" => MAIDENBOT_WWW }

    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_cors_grant MAIDENBOT_WWW
    assert_equal expected_catalog, response.parsed_body
  end

  test "www maidenbot head grants access without a response body" do
    head "/api/ships", headers: { "Origin" => MAIDENBOT_WWW }

    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_empty response.body
    assert_cors_grant MAIDENBOT_WWW
  end

  test "www maidenbot simple get preflight grants only the catalog methods" do
    options "/api/ships", headers: {
      "Origin" => MAIDENBOT_WWW,
      "Access-Control-Request-Method" => "GET"
    }

    assert_response :ok
    assert_cors_grant MAIDENBOT_WWW, vary: false
    assert_equal "600", response.headers["Access-Control-Max-Age"]
    assert_nil response.headers["Access-Control-Allow-Headers"]
    assert_empty response.body
  end

  EXISTING_ORIGINS.each do |origin|
    test "existing catalog grants and preflights remain intact for #{origin}" do
      CATALOG_PATHS.each do |path|
        get path, headers: { "Origin" => origin }

        assert_response :ok
        assert_equal "application/json", response.media_type
        assert_cors_grant origin
        if path == "/api/ships"
          assert_equal expected_catalog, response.parsed_body
        else
          assert_kind_of Array, response.parsed_body.fetch("data")
        end

        options path, headers: {
          "Origin" => origin,
          "Access-Control-Request-Method" => "GET",
          "Access-Control-Request-Headers" => "Content-Type"
        }

        assert_response :ok
        assert_cors_grant origin, vary: false
        assert_equal "Content-Type", response.headers["Access-Control-Allow-Headers"]
        assert_equal "600", response.headers["Access-Control-Max-Age"]
      end
    end
  end

  test "no origin preserves the anonymous catalog schema filters and vary" do
    get "/api/ships"

    assert_response :ok
    assert_equal "application/json", response.media_type
    assert_equal expected_catalog, response.parsed_body
    assert_no_cors_grant
    assert_includes response.headers.fetch("Vary").split(/,\s*/), "Origin"
    without_origin = response.parsed_body

    get "/api/ships", headers: { "Origin" => MAIDENBOT_WWW }

    assert_cors_grant MAIDENBOT_WWW
    assert_equal without_origin, response.parsed_body
  end

  test "catalog legacy fallbacks and empty response are preserved" do
    @ship.update!(company_name: nil, hp: nil, is_docking: false)
    get "/api/ships", headers: { "Origin" => MAIDENBOT_WWW }

    assert_response :ok
    assert_equal expected_catalog.first.merge(
      "manufacturer" => "Unknown", "hp" => "45", "requiresdocking" => "false"
    ), response.parsed_body.fetch(0)
    assert_cors_grant MAIDENBOT_WWW

    @ship.update!(is_spaceship: false)
    get "/api/ships", headers: { "Origin" => MAIDENBOT_WWW }

    assert_response :ok
    assert_equal [], response.parsed_body
    assert_cors_grant MAIDENBOT_WWW
  end

  [
    "https://example.com",
    "http://www.maidenbot.com",
    "https://www.maidenbot.com.example.com",
    "https://www.maidenbot.com:444",
    "null"
  ].each do |origin|
    test "unapproved origin #{origin} gets no catalog or preflight grant" do
      get "/api/ships", headers: { "Origin" => origin }

      assert_response :ok
      assert_equal expected_catalog, response.parsed_body
      assert_no_cors_grant
      assert_includes response.headers.fetch("Vary").split(/,\s*/), "Origin"

      options "/api/ships", headers: {
        "Origin" => origin,
        "Access-Control-Request-Method" => "GET"
      }

      assert_no_cors_grant
    end
  end

  [
    "/api/locations", "/api/commodities", "/api/ships.json",
    "/api/cors-not-a-route", "/api/ships/cors-not-a-route",
    "/api/ships/dump_cargo", "/api/ships/deliver_ship", "/api/status"
  ].each do |path|
    test "www maidenbot has no grant outside approved path #{path}" do
      get path, headers: { "Origin" => MAIDENBOT_WWW }

      assert_no_cors_grant
      assert_response(CATALOG_PATHS.include?(path) || path.end_with?(".json") ? :ok : :not_found)

      options path, headers: {
        "Origin" => MAIDENBOT_WWW,
        "Access-Control-Request-Method" => "GET"
      }

      assert_no_cors_grant
    end
  end

  %w[POST PUT PATCH DELETE].each do |method|
    test "www maidenbot cannot gain a grant for unsupported method #{method}" do
      options "/api/ships", headers: {
        "Origin" => MAIDENBOT_WWW,
        "Access-Control-Request-Method" => method
      }

      assert_no_cors_grant

      # These methods have no canonical /api/ships route and cannot mutate data.
      public_send method.downcase, "/api/ships", headers: { "Origin" => MAIDENBOT_WWW }

      assert_response :not_found
      assert_no_cors_grant
    end
  end

  test "www maidenbot custom header preflight is not authorized by default" do
    options "/api/ships", headers: {
      "Origin" => MAIDENBOT_WWW,
      "Access-Control-Request-Method" => "GET",
      "Access-Control-Request-Headers" => "X-Unapproved-Header"
    }

    assert_no_cors_grant
    assert_nil response.headers["Access-Control-Allow-Headers"]
  end

  test "alternating origins do not reuse another origins response permission" do
    [MAIDENBOT_WWW, "https://example.com", nil, "https://maidenbot.com", MAIDENBOT_WWW].each do |origin|
      get "/api/ships", headers: origin ? { "Origin" => origin } : {}

      assert_response :ok
      assert_equal expected_catalog, response.parsed_body
      assert_includes response.headers.fetch("Vary").split(/,\s*/), "Origin"
      if [MAIDENBOT_WWW, "https://maidenbot.com"].include?(origin)
        assert_cors_grant origin
      else
        assert_no_cors_grant
      end
    end
  end

  test "query strings and normalized trailing slash preserve canonical access" do
    ["/api/ships?catalog=public", "/api/ships/"].each do |path|
      get path, headers: { "Origin" => MAIDENBOT_WWW }

      assert_response :ok
      assert_equal expected_catalog, response.parsed_body
      assert_cors_grant MAIDENBOT_WWW
    end
  end

  test "format alias remains ungranted even for existing origins" do
    EXISTING_ORIGINS.each do |origin|
      get "/api/ships.json", headers: { "Origin" => origin }

      assert_response :ok
      assert_equal expected_catalog, response.parsed_body
      assert_no_cors_grant
    end
  end

  test "protected cargo operation retains authentication and no browser grant" do
    post "/api/ships/dump_cargo",
      params: { ship_guid: "nonexistent-cors-test-ship", secret_guid: "invalid-cors-test-secret" },
      headers: { "Origin" => MAIDENBOT_WWW }, as: :json

    assert_response :unauthorized
    assert_equal({ "Status" => "error", "Message" => "", "ErrorText" => "Unauthorized" }, response.parsed_body)
    assert_no_cors_grant
  end

  private

  def assert_cors_grant(origin, vary: true)
    # Exact scalar equality rejects duplicate/comma-joined/wildcard grants.
    assert_equal origin, response.headers["Access-Control-Allow-Origin"]
    assert_nil response.headers["Access-Control-Allow-Credentials"]
    assert_equal %w[GET HEAD OPTIONS], response.headers.fetch("Access-Control-Allow-Methods").split(/,\s*/)
    assert_includes response.headers.fetch("Vary").split(/,\s*/), "Origin" if vary
  end

  def assert_no_cors_grant
    assert_nil response.headers["Access-Control-Allow-Origin"]
    assert_nil response.headers["Access-Control-Allow-Credentials"]
  end

  def expected_catalog
    [{
      "shipname" => "Catalog Ship", "manufacturer" => "Drake",
      "cargocapacity" => "100", "requiresdocking" => "true",
      "filename" => "/catalog/ship.png", "keel" => "111", "msrp" => "295",
      "qfuel" => "2500.0", "hp" => "80", "category" => "ship", "isactive" => "1"
    }]
  end
end
