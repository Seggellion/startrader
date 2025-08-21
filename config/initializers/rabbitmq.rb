
Rails.application.config.after_initialize do
  begin
    host = Setting.get("rabbitmq_host")     || ENV["RABBITMQ_HOST"]     || "localhost"
    user = Setting.get("rabbitmq_username") || ENV["RABBITMQ_USERNAME"] || "guest"
    pass = Setting.get("rabbitmq_password") || ENV["RABBITMQ_PASSWORD"] || "guest"

    RABBITMQ_CONN = Bunny.new(host: host, user: user, password: pass, automatically_recover: true).tap(&:start)
    RABBITMQ_CHANNEL = RABBITMQ_CONN.create_channel
  rescue => e
    Rails.logger.warn "RabbitMQ not available at boot: #{e.class}: #{e.message}"
    RABBITMQ_CONN = nil
    RABBITMQ_CHANNEL = nil
  end
end

at_exit { RABBITMQ_CONN&.close rescue nil }