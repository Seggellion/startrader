require "test_helper"
require_relative "../support/fake_rabbitmq"

class RabbitmqConnectionTest < ActiveSupport::TestCase
  ENV_KEYS = %w[
    RABBITMQ_HOST RABBITMQ_USERNAME RABBITMQ_PASSWORD
    RABBITMQ_DEV_HOST RABBITMQ_DEV_USERNAME RABBITMQ_DEV_PASSWORD
  ].freeze

  setup do
    Setting.delete_all
    RabbitmqConnection.reset!
    @original_env = ENV_KEYS.index_with { |key| ENV[key] }
    ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    RabbitmqConnection.reset!
    @original_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  test "normalizes case and whitespace and defaults blank input to prod" do
    assert_equal "dev", RabbitmqConnection.normalize("  DEV \n")
    assert_equal "prod", RabbitmqConnection.normalize("Prod")
    assert_nil RabbitmqConnection.normalize("   ")

    assert_equal "prod", RabbitmqConnection.normalize!(nil)
    assert_equal "prod", RabbitmqConnection.normalize!("")
    assert_equal "dev", RabbitmqConnection.normalize!(" Dev ")
  end

  test "rejects unsupported environments" do
    refute RabbitmqConnection.valid_environment?("staging")
    refute RabbitmqConnection.valid_environment?(nil)
    assert RabbitmqConnection.valid_environment?("PROD")
    assert RabbitmqConnection.valid_environment?("dev")

    error = assert_raises(RabbitmqConnection::UnknownEnvironmentError) do
      RabbitmqConnection.normalize!("staging")
    end
    assert_includes error.message, "staging"
  end

  test "production credentials keep the existing setting, env, and default precedence" do
    assert_equal({ host: "localhost", user: "guest", password: "guest" },
                 RabbitmqConnection.credentials_for("prod"))

    ENV["RABBITMQ_HOST"] = "env-prod-host"
    ENV["RABBITMQ_USERNAME"] = "env-prod-user"
    assert_equal "env-prod-host", RabbitmqConnection.credentials_for("prod")[:host]
    assert_equal "env-prod-user", RabbitmqConnection.credentials_for("prod")[:user]

    Setting.create!(key: "rabbitmq_host", value: "setting-prod-host", setting_type: "text")
    assert_equal "setting-prod-host", RabbitmqConnection.credentials_for("prod")[:host]
  end

  test "development credentials read their own keys and never borrow production values" do
    Setting.create!(key: "rabbitmq_host", value: "setting-prod-host", setting_type: "text")
    Setting.create!(key: "rabbitmq_username", value: "prod-user", setting_type: "text")

    assert_nil RabbitmqConnection.credentials_for("dev")[:host]
    refute RabbitmqConnection.configured?("dev")
    assert RabbitmqConnection.configured?("prod")

    ENV["RABBITMQ_DEV_HOST"] = "env-dev-host"
    assert_equal "env-dev-host", RabbitmqConnection.credentials_for("dev")[:host]

    Setting.create!(key: "rabbitmq_dev_host", value: "setting-dev-host", setting_type: "text")
    Setting.create!(key: "rabbitmq_dev_username", value: "dev-user", setting_type: "text")
    Setting.create!(key: "rabbitmq_dev_password", value: "dev-password", setting_type: "text")

    dev = RabbitmqConnection.credentials_for("dev")
    assert_equal "setting-dev-host", dev[:host]
    assert_equal "dev-user", dev[:user]
    assert_equal "dev-password", dev[:password]
    assert_equal "setting-prod-host", RabbitmqConnection.credentials_for("prod")[:host]
  end

  test "an unconfigured development environment raises instead of falling back to production" do
    configure_prod!

    FakeRabbitmq.stub_bunny do
      error = assert_raises(RabbitmqConnection::NotConfiguredError) do
        RabbitmqConnection.channel_for("dev")
      end
      assert_includes error.message, "rabbitmq_dev_host"
      assert_includes error.message, "RABBITMQ_DEV_HOST"

      assert_equal "prod-host", RabbitmqConnection.channel_for("prod").host
    end
  end

  test "each environment gets its own memoized connection and channel" do
    configure_prod!
    configure_dev!

    FakeRabbitmq.stub_bunny do
      prod_channel = RabbitmqConnection.channel_for("prod")
      dev_channel = RabbitmqConnection.channel_for("dev")

      refute_same prod_channel, dev_channel
      assert_equal "prod-host", prod_channel.host
      assert_equal "dev-host", dev_channel.host
      refute_same RabbitmqConnection.connection_for("prod"), RabbitmqConnection.connection_for("dev")

      assert_same prod_channel, RabbitmqConnection.channel_for("prod")
      assert_same dev_channel, RabbitmqConnection.channel_for(" DEV ")
    end
  end

  test "an unavailable development broker does not disturb production" do
    configure_prod!
    configure_dev!

    FakeRabbitmq.stub_bunny(unreachable: ["dev-host"]) do
      assert_raises(RabbitmqConnection::UnavailableError) { RabbitmqConnection.channel_for("dev") }

      assert_equal "prod-host", RabbitmqConnection.channel_for("prod").host

      # The failure is not cached as a usable channel, and it never resolves to prod.
      assert_raises(RabbitmqConnection::UnavailableError) { RabbitmqConnection.channel_for("dev") }
    end
  end

  test "an unavailable production broker does not redirect traffic to development" do
    configure_prod!
    configure_dev!

    FakeRabbitmq.stub_bunny(unreachable: ["prod-host"]) do
      error = assert_raises(RabbitmqConnection::UnavailableError) { RabbitmqConnection.channel_for("prod") }
      assert_includes error.message, "prod"

      assert_equal "dev-host", RabbitmqConnection.channel_for("dev").host
    end
  end

  test "connection failures never leak credentials into the error or the log" do
    configure_prod!
    configure_dev!(user: "dev-secret-user", password: "dev-secret-password")

    logged = capture_rails_log do
      FakeRabbitmq.stub_bunny(unreachable: ["dev-host"]) do
        error = assert_raises(RabbitmqConnection::UnavailableError) { RabbitmqConnection.channel_for("dev") }

        assert_includes error.message, "dev"
        refute_includes error.message, "dev-secret-user"
        refute_includes error.message, "dev-secret-password"
      end
    end

    assert_includes logged, "rabbitmq_connect_failed"
    assert_includes logged, %(environment="dev")
    refute_includes logged, "dev-secret-user"
    refute_includes logged, "dev-secret-password"
  end

  test "a closed connection is reopened on the next request" do
    configure_prod!

    FakeRabbitmq.stub_bunny do
      first = RabbitmqConnection.channel_for("prod")
      first.session.close

      second = RabbitmqConnection.channel_for("prod")
      refute_same first, second
      assert second.open?
    end
  end

  test "boot warms configured environments, skips unconfigured ones, and never raises" do
    configure_prod!

    logged = capture_rails_log do
      FakeRabbitmq.stub_bunny(unreachable: ["prod-host"]) do
        RabbitmqConnection.connect_all!
      end
    end

    assert_includes logged, "rabbitmq_boot_connect_failed"
    assert_includes logged, "rabbitmq_not_configured"
  end

  test "shutdown closes every environment independently" do
    configure_prod!
    configure_dev!

    FakeRabbitmq.stub_bunny do
      prod = RabbitmqConnection.connection_for("prod")
      dev = RabbitmqConnection.connection_for("dev")

      RabbitmqConnection.close_all!

      refute prod.open?
      refute dev.open?
    end
  end

  private

  def configure_prod!(host: "prod-host", user: "prod-user", password: "prod-password")
    Setting.create!(key: "rabbitmq_host", value: host, setting_type: "text")
    Setting.create!(key: "rabbitmq_username", value: user, setting_type: "text")
    Setting.create!(key: "rabbitmq_password", value: password, setting_type: "text")
  end

  def configure_dev!(host: "dev-host", user: "dev-user", password: "dev-password")
    Setting.create!(key: "rabbitmq_dev_host", value: host, setting_type: "text")
    Setting.create!(key: "rabbitmq_dev_username", value: user, setting_type: "text")
    Setting.create!(key: "rabbitmq_dev_password", value: password, setting_type: "text")
  end

  def capture_rails_log
    buffer = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(buffer)
    yield
    buffer.string
  ensure
    Rails.logger = original_logger
  end
end
