module Resque
  module StuckQueue

    require 'logger'
    # defaults
    HEARTBEAT_KEY        = "resque-stuck-queue"
    TRIGGERED_KEY        = "resque-stuck-queue-last-triggered"
    HEARTBEAT_TIMEOUT    = 20 * 60                  # check/refresh every 20 mins.
    TRIGGER_TIMEOUT      = 40 * 60                  # warn/trigger after an hour (with 20 min heartbeat time).
    LOGGER               = Logger.new($stdout)
    # must be called by convention: type_handler
    TRIGGERED_HANDLER    = proc { |queue_name, lag| Resque::StuckQueue::LOGGER.info("Shit gone bad with them queues...on #{queue_name}. Lag time is #{lag}") }
    RECOVERED_HANDLER    = proc { |queue_name, lag| Resque::StuckQueue::LOGGER.info("recovered queue phew #{queue_name}. Lag time is #{lag}") }

    class Config < Hash

      OPTIONS_DESCRIPTIONS = {
        :triggered_handler  => "set to what gets triggered when resque-stuck-queue will detect the latest heartbeat is older than the trigger_timeout time setting.\n\tExample:\n\tResque::StuckQueue.config[:triggered_handler] = proc { |queue_name, lagtime| send_email('queue \#{queue_name} isnt working, aaah the daemons') }",
        :recovered_handler  => "set to what gets triggered when resque-stuck-queue has triggered a problem, but then detects the queue went back down to functioning well again(it wont trigger again until it has recovered).\n\tExample:\n\tResque::StuckQueue.config[:recovered_handler] = proc { |queue_name, lagtime| send_email('phew, queue \#{queue_name} is ok') }",
        :heartbeat          => "set to how often to push that 'heartbeat' job to refresh the latest time it worked.\n\tExample:\n\tResque::StuckQueue.config[:heartbeat] = 5.minutes",
        :trigger_timeout    => "set to how much of a resque work lag you are willing to accept before being notified. note: take the :heartbeat setting into account when setting this timeout.\n\tExample:\n\tResque::StuckQueue.config[:trigger_timeout] = 55.minutes",
        :redis              => "set the Redis instance StuckQueue will use",
        :heartbeat_key      => "optional, name of keys to keep track of the last good resque heartbeat time",
        :triggered_key      => "optional, name of keys to keep track of the last trigger time",
        :logger             => "optional, pass a Logger. Default a ruby logger will be instantiated. Needs to respond to that interface.",
        :queues             => "optional, monitor specific queues you want to send a heartbeat/monitor to. default is :app",
        :abort_on_exception => "optional, if you want the resque-stuck-queue threads to explicitly raise, default is false",
        :heartbeat_job        => "optional, your own custom refreshing job. if you are using something other than resque",
      }

      OPTIONS = OPTIONS_DESCRIPTIONS.keys

      def []=(k,v)
        validate_key_exists!(k)
        super(k,v)
      end

      def [](k)
        validate_key_exists!(k)
        super(k)
      end

      class NoConfigError < StandardError; end

      def validate_key_exists!(k)
        if ! OPTIONS.include?(k)
          raise NoConfigError, "no such config key #{k} exists!"
        end
      end

      def description_for(k)
        OPTIONS_DESCRIPTIONS[k.to_sym]
      end

      def pretty_descriptions
        out = "\n"
        OPTIONS_DESCRIPTIONS.map{|key,msg|
          out << "#{key}:\n\t#{msg}\n\n"
        }
        out
      end

    end
  end
end
