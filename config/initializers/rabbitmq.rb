# RabbitMQ connections are owned by RabbitmqConnection, which keeps one
# independent Bunny connection/channel per environment ("prod" and "dev").
#
# Boot only warms the connections. Every environment connects, fails, and
# recovers on its own, and any environment that is unavailable at boot is
# reconnected lazily the next time something publishes to it.
Rails.application.config.after_initialize do
  # Test preparation must never open either real broker. Connection tests
  # supply explicit fake connections instead.
  next if Rails.env.test?

  RabbitmqConnection.connect_all!
end

at_exit { RabbitmqConnection.close_all! rescue nil }
