require "monitor"

# Registry of long lived Bunny connections, one per logical RabbitMQ
# environment ("prod" and "dev").
#
# Each environment is configured, connected, and torn down independently so a
# broker outage on one never affects the other, and so a message is never
# silently re-routed between them. Callers ask for a channel by environment
# name; nothing here reads request state or mutates a shared "current"
# environment.
class RabbitmqConnection
  PRODUCTION  = "prod".freeze
  DEVELOPMENT = "dev".freeze
  ENVIRONMENTS = [PRODUCTION, DEVELOPMENT].freeze
  DEFAULT_ENVIRONMENT = PRODUCTION

  Error                   = Class.new(StandardError)
  UnknownEnvironmentError = Class.new(Error)
  NotConfiguredError      = Class.new(Error)
  UnavailableError        = Class.new(Error)

  # Railpress Setting keys, ENV fallbacks, and last-resort defaults per
  # environment. Production keeps its historical keys and defaults. Development
  # has no default host on purpose: an unconfigured dev environment must fail
  # loudly instead of quietly connecting to whatever runs on localhost.
  CONFIG_KEYS = {
    PRODUCTION => {
      host:     { setting: "rabbitmq_host",         env: "RABBITMQ_HOST",         default: "localhost" },
      user:     { setting: "rabbitmq_username",     env: "RABBITMQ_USERNAME",     default: "guest" },
      password: { setting: "rabbitmq_password",     env: "RABBITMQ_PASSWORD",     default: "guest" }
    }.freeze,
    DEVELOPMENT => {
      host:     { setting: "rabbitmq_dev_host",     env: "RABBITMQ_DEV_HOST",     default: nil },
      user:     { setting: "rabbitmq_dev_username", env: "RABBITMQ_DEV_USERNAME", default: "guest" },
      password: { setting: "rabbitmq_dev_password", env: "RABBITMQ_DEV_PASSWORD", default: "guest" }
    }.freeze
  }.freeze

  REGISTRY_MUTEX = Mutex.new

  class << self
    # "  DEV " => "dev". Blank input returns nil so callers can decide whether
    # blank means "use the default" or "reject the request".
    def normalize(value)
      value.to_s.strip.downcase.presence
    end

    def valid_environment?(value)
      ENVIRONMENTS.include?(normalize(value))
    end

    # Normalizes, defaulting blank input to production, and raises on anything
    # that is not a supported environment.
    def normalize!(value)
      environment = normalize(value) || DEFAULT_ENVIRONMENT
      return environment if ENVIRONMENTS.include?(environment)

      raise UnknownEnvironmentError,
        "Unknown RabbitMQ environment #{environment.inspect}. Expected one of: #{ENVIRONMENTS.join(', ')}."
    end

    def configured?(environment)
      credentials_for(environment)[:host].present?
    rescue Error
      false
    end

    # Credentials for one environment, resolved Setting -> ENV -> default.
    # Never log or render the returned hash.
    def credentials_for(environment)
      keys = CONFIG_KEYS.fetch(normalize!(environment))

      keys.transform_values do |source|
        setting_value(source[:setting]) || ENV[source[:env]].presence || source[:default]
      end
    end

    def channel_for(environment)
      with_environment(environment) do |state|
        open!(state) unless usable?(state)
        state[:channel]
      end
    end

    def connection_for(environment)
      with_environment(environment) do |state|
        open!(state) unless usable?(state)
        state[:connection]
      end
    end

    # Boot hook. Warms every configured environment without ever raising, so a
    # broker that is down at boot cannot stop the application from starting and
    # cannot stop the other environment from connecting.
    def connect_all!
      ENVIRONMENTS.each do |environment|
        begin
          unless configured?(environment)
            Rails.logger.info(%(event="rabbitmq_not_configured" environment=#{environment.inspect}))
            next
          end

          channel_for(environment)
        rescue StandardError => error
          Rails.logger.warn(
            %(event="rabbitmq_boot_connect_failed" environment=#{environment.inspect} ) +
              "error_class=#{error.class.name.inspect}"
          )
        end
      end
    end

    # Shutdown hook. Closes every environment independently and never raises.
    def close_all!
      ENVIRONMENTS.each do |environment|
        begin
          with_environment(environment) { |state| discard!(state) }
        rescue StandardError
          nil
        end
      end

      nil
    end

    # Drops every cached connection so the next call reconnects. Used by tests
    # and by the console; safe to call at any time.
    def reset!
      close_all!
    end

    private

    # Per environment state, each with its own monitor. The registry lives on
    # the application config object rather than in class level ivars so
    # development code reloading cannot orphan open sockets. The outer hash is
    # built once and never mutated again; only the inner per environment hashes
    # change, and only while that environment's monitor is held.
    def registry
      REGISTRY_MUTEX.synchronize do
        config = Rails.application.config
        store = config.x.rabbitmq_registry

        unless store.is_a?(Hash)
          store = ActiveSupport::OrderedOptions.new
          config.x.rabbitmq_registry = store
        end

        store[:environments] ||= ENVIRONMENTS.index_with do |environment|
          { environment: environment, monitor: Monitor.new, connection: nil, channel: nil }
        end
        store[:environments]
      end
    end

    def with_environment(environment)
      state = registry.fetch(normalize!(environment))
      state[:monitor].synchronize { yield(state) }
    end

    def usable?(state)
      return false if state[:connection].nil? || state[:channel].nil?

      open?(state[:connection]) && open?(state[:channel])
    end

    def open?(object)
      return true unless object.respond_to?(:open?)

      object.open?
    end

    def open!(state)
      environment = state[:environment]
      credentials = credentials_for(environment)
      raise NotConfiguredError, not_configured_message(environment) if credentials[:host].blank?

      discard!(state)

      connection = build_connection(credentials)
      state[:connection] = connection
      state[:channel]    = connection.create_channel

      Rails.logger.info(
        %(event="rabbitmq_connected" environment=#{environment.inspect} host=#{credentials[:host].inspect})
      )

      state[:channel]
    rescue Error
      raise
    rescue StandardError => error
      discard!(state)
      message = sanitize(error.message, credentials)

      Rails.logger.warn(
        %(event="rabbitmq_connect_failed" environment=#{environment.inspect} ) +
          "host=#{credentials&.dig(:host).inspect} error_class=#{error.class.name.inspect} " \
          "error_message=#{message.inspect}"
      )

      raise UnavailableError,
        "RabbitMQ environment #{environment.inspect} is unavailable: #{error.class}: #{message}"
    end

    def build_connection(credentials)
      Bunny.new(
        host: credentials[:host],
        user: credentials[:user],
        password: credentials[:password],
        automatically_recover: true
      ).tap(&:start)
    end

    def discard!(state)
      channel    = state[:channel]
      connection = state[:connection]
      state[:channel]    = nil
      state[:connection] = nil

      close_quietly(channel)
      close_quietly(connection)
    end

    def close_quietly(object)
      object&.close
    rescue StandardError
      nil
    end

    def setting_value(key)
      Setting.get(key).presence
    rescue StandardError => error
      Rails.logger.warn(
        %(event="rabbitmq_setting_lookup_failed" setting=#{key.inspect} error_class=#{error.class.name.inspect})
      )
      nil
    end

    # Bunny surfaces the configured username inside authentication failure
    # messages, so strip credentials out of anything we log or re-raise.
    def sanitize(message, credentials)
      text = message.to_s
      return text if credentials.blank?

      [credentials[:user], credentials[:password]].each do |secret|
        next if secret.blank?

        text = text.gsub(secret.to_s, "[REDACTED]")
      end

      text
    end

    def not_configured_message(environment)
      host_keys = CONFIG_KEYS.fetch(environment)[:host]

      "RabbitMQ environment #{environment.inspect} is not configured. " \
        "Create the #{host_keys[:setting].inspect} Railpress setting or set #{host_keys[:env]}."
    end
  end
end
