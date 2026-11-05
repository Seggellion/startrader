# Select once at departure. Explicit requests and existing receipts always win
# over a configured shard default; queued/saved journeys never change brokers.
class GateTravelRouting
  Selection = Struct.new(:environment, :source, keyword_init: true)

  def self.setting_key(shard_id)
    "gate_rabbitmq_default_shard_#{Integer(shard_id)}"
  end

  def self.resolve(user_ship:, shard:, travel_guid:, requested_environment: nil)
    explicit = RabbitmqConnection.normalize(requested_environment)
    if explicit
      return Selection.new(environment:RabbitmqConnection.normalize!(explicit),source:'request')
    end
    receipt = TravelRequestReceipt.find_by(travel_guid:travel_guid,user_ship_id:user_ship.id)
    if receipt && receipt.travel_snapshot['ship_travel_type']=='gate_travel'
      return Selection.new(environment:RabbitmqConnection.normalize!(receipt.travel_snapshot['rabbitmq_environment']),
        source:'receipt')
    end
    configured = RabbitmqConnection.normalize(Setting.get(setting_key(shard.id)))
    if configured
      unless RabbitmqConnection.valid_environment?(configured)
        raise TravelLifecycle::Error.new('invalid_rabbitmq_configuration',
          'Jump routing needs administrator review.')
      end
      return Selection.new(environment:configured,source:'shard_default')
    end
    Selection.new(environment:RabbitmqConnection::DEFAULT_ENVIRONMENT,source:'global_default')
  end
end
