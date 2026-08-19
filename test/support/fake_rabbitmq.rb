# In-memory stand-ins for the Bunny connection/channel/exchange layer.
#
# Tests must never open a socket to a real broker, so every test that exercises
# RabbitmqConnection wraps its work in FakeRabbitmq.stub_bunny and inspects what
# was published instead.
module FakeRabbitmq
  class Exchange
    attr_reader :channel, :name, :options

    def initialize(channel, name, options)
      @channel = channel
      @name = name
      @options = options
    end

    def publish(message, **publish_options)
      channel.publications << {
        exchange: name,
        exchange_options: options,
        message: message
      }.merge(publish_options)
    end
  end

  class Channel
    attr_reader :session, :publications, :topics

    def initialize(session)
      @session = session
      @publications = []
      @topics = []
      @open = true
    end

    def topic(name, **options)
      @topics << [name, options]
      Exchange.new(self, name, options)
    end

    def host
      session.options[:host]
    end

    def open?
      @open
    end

    def close
      @open = false
    end
  end

  class Session
    attr_reader :options

    def initialize(options)
      @options = options
      @open = false
    end

    def start
      @open = true
      self
    end

    def create_channel
      Channel.new(self)
    end

    def host
      options[:host]
    end

    def open?
      @open
    end

    def close
      @open = false
    end
  end

  # Replaces Bunny.new for the duration of the block. Any host listed in
  # `unreachable:` raises on connect, which is how broker outages are simulated.
  # The raised message deliberately embeds the credentials, mirroring Bunny's
  # own authentication failures, so credential redaction can be asserted.
  def self.stub_bunny(unreachable: [])
    factory = lambda do |*args, **kwargs|
      options = kwargs.presence || (args.last.is_a?(Hash) ? args.last : {})

      if unreachable.include?(options[:host])
        raise "Could not establish TCP connection to #{options[:host]}. " \
          "Username: #{options[:user]}, password: #{options[:password]}"
      end

      Session.new(options)
    end

    Bunny.stub(:new, factory) { yield }
  end

  # Records which environment each publish asked for without opening anything.
  class ChannelRecorder
    attr_reader :requested_environments, :channels

    def initialize
      @requested_environments = []
      @channels = Hash.new { |hash, environment| hash[environment] = Channel.new(Session.new(host: "#{environment}-host")) }
    end

    def to_proc
      lambda do |environment|
        @requested_environments << environment
        @channels[environment]
      end
    end

    def publications_for(environment)
      @channels.key?(environment) ? @channels[environment].publications : []
    end
  end
end
