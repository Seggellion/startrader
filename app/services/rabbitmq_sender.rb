class RabbitmqSender
  EXCHANGE_NAME = "MaidenB0T_events".freeze

  # Streamer check-status events are not part of the ShipTravel workflow and
  # always go to production.
  def self.send_event(streamer)
    routing_key = "maidenb0tevents.#{streamer.downcase}"
    tag_id      = routing_key
    message     = "Seggellion|CheckStatus"

    publish(
      environment: RabbitmqConnection::DEFAULT_ENVIRONMENT,
      routing_key: routing_key,
      tag_id: tag_id,
      message: message
    )

    Rails.logger.info "Sent #{message} to #{EXCHANGE_NAME} with routing key #{routing_key} and tagId #{tag_id}"
  end

  # The destination broker comes from the environment recorded on the travel
  # when it began, never from whatever request happens to be processing the
  # arrival.
  def self.send_ship_report(travel)
    ship = travel.user_ship
    user = ship.user
    shard = ship.shard
    shard_name = shard.name.downcase
    routing_key   = "maidenb0tevents.#{shard_name}"
    tag_id        = routing_key
    environment   = RabbitmqConnection.normalize!(travel.rabbitmq_environment)
    secret_guid   = Setting.get('secret_guid')

    # Build the message string in the expected format
    message = [
      shard_name,
      "ShipArrival",
      user.uid,
      travel.departure_tick,
      travel.arrival_tick,
      shard.channel_uuid,
      user.username,
      ship.guid,
      ship.status,
      ship.ship.model,
      secret_guid,
      travel.from_location.name,
      travel.to_location.name,
      travel.travel_guid
    ].join("|")

    publish(
      environment: environment,
      routing_key: routing_key,
      tag_id: tag_id,
      message: message
    )

    Rails.logger.info "Sent ship report to #{EXCHANGE_NAME} on rabbitmq environment #{environment} " \
      "with routing key #{routing_key}: #{redact_secret(message, secret_guid)}"
  end

  def self.publish(environment:, routing_key:, tag_id:, message:)
    channel = RabbitmqConnection.channel_for(environment)
    exchange = channel.topic(EXCHANGE_NAME, durable: true)
    exchange.publish(message, routing_key: routing_key, headers: { tagId: tag_id }, persistent: true)
  end
  private_class_method :publish

  def self.redact_secret(message, secret)
    return message if secret.blank?

    message.gsub(secret.to_s, "[REDACTED]")
  end
  private_class_method :redact_secret
end
