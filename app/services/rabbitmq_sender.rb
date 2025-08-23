class RabbitmqSender
  def self.send_event(streamer)
    exchange_name = "MaidenB0T_events"
    routing_key   = "maidenb0tevents.#{streamer.downcase}"
    tag_id        = routing_key
    message       = "Seggellion|CheckStatus"

    exchange = RABBITMQ_CHANNEL.topic(exchange_name, durable: true)
    exchange.publish(message, routing_key: routing_key, headers: { tagId: tag_id }, persistent: true)

    Rails.logger.info "Sent #{message} to #{exchange_name} with routing key #{routing_key} and tagId #{tag_id}"
  end

  def self.send_ship_report(travel)
    ship = travel.user_ship
    user = ship.user
    shard = ship.shard
    shard_name = shard.name.downcase
    exchange_name = "MaidenB0T_events"
    routing_key   = "maidenb0tevents.#{shard_name}"
    tag_id        = routing_key

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
      travel.to_location.name
    ].join("|")

    exchange = RABBITMQ_CHANNEL.topic(exchange_name, durable: true)
    exchange.publish(message, routing_key: routing_key, headers: { tagId: tag_id }, persistent: true)

    Rails.logger.info "Sent ship report to #{exchange_name} with routing key #{routing_key}: #{message}"
  end
end
