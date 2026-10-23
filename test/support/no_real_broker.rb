require 'bunny'

# Fake connections supplied by tests remain usable. An unstubbed real Bunny
# session must fail before opening a socket or publishing an external event.
module NoRealBrokerInTests
  def start
    raise IOError, 'Real RabbitMQ connections are disabled in tests; supply a fake connection'
  end
end
Bunny::Session.prepend(NoRealBrokerInTests)
