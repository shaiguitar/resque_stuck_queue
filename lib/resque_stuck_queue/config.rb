module Resque
  module StuckQueue

    require 'logger'
    # defaults
    HEARTBEAT_INTERVAL   = 5 * 60                   # send heartbeat job every 5 minutes
    WATCHER_INTERVAL     = 5                        # check key is udpated every 5 seconds.

    TRIGGER_TIMEOUT      = 60 * 60                  # warn/trigger after an hour of lagtime.

    # must be called by convention: type_handler
    TRIGGERED_HANDLER    = proc { |queue_name, lag| Resque::StuckQueue::LOGGER.info("Shit gone bad with them queues...on #{queue_name}. Lag time is #{lag}") }
    RECOVERED_HANDLER    = proc { |queue_name, lag| Resque::StuckQueue::LOGGER.info("recovered queue phew #{queue_name}. Lag time is #{lag}") }

    LOGGER               = Logger.new($stdout)
    HEARTBEAT_KEY        = "resque-stuck-queue"
    TRIGGERED_KEY        = "resque-stuck-queue-last-triggered"

    class Config < Hash

      OPTIONS_DESCRIPTIONS = {
        :triggered_handler  => "set to what gets triggered when resque-stuck-queue will detect the latest heartbeat is older than the trigger_timeout time setting.\n\tExample:\n\tResque::StuckQueue.config[:triggered_handler] = proc { |queue_name, lagtime| send_email('queue \#{queue_name} isnt working, aaah the daemons') }",
        :recovered_handler  => "set to what gets triggered when resque-stuck-queue has triggered a problem, but then detects the queue went back down to functioning well again(it wont trigger again until it has recovered).\n\tExample:\n\tResque::StuckQueue.config[:recovered_handler] = proc { |queue_name, lagtime| send_email('phew, queue \#{queue_name} is ok') }",
        :heartbeat_interval => "set to how often to push the 'heartbeat' job which will refresh the latest working time.\n\tExample:\n\tResque::StuckQueue.config[:heartbeat_interval] = 5.minutes",
        :watcher_interval            => "set to how often to check to see when the last time it worked was.\n\tExample:\n\tResque::StuckQueue.config[:watcher_interval] = 1.minute",
        :trigger_timeout    => "set to how much of a resque work lag you are willing to accept before being notified. note: take the :watcher_interval setting into account when setting this timeout.\n\tExample:\n\tResque::StuckQueue.config[:trigger_timeout] = 9.minutes",
        :redis              => "set the Redis StuckQueue will use. Either a Redis or Redis::Namespace instance.",
        :heartbeat_key      => "optional, name of keys to keep track of the last good resque heartbeat time",
        :triggered_key      => "optional, name of keys to keep track of the last trigger time",
        :logger             => "optional, pass a Logger. Default a ruby logger will be instantiated. Needs to respond to that interface.",
        :queues             => "optional, monitor specific queues you want to send a heartbeat/monitor to. default is [:app]",
        :abort_on_exception => "optional, if you want the resque-stuck-queue threads to explicitly raise, default is false",
        :heartbeat_job      => "optional, your own custom refreshing job. if you are using something other than resque",
        :enable_signals     => "optional, allow resque::stuck's signal_handlers which do mostly nothing at this point.",
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

      REQUIRED_KEYS = [:redis]
      def validate_required_keys!
        REQUIRED_KEYS.each do |k|
          if self[k].nil?
            raise NoConfigError, "You must set config[:#{k}]"
          end
        end
      end

      class NoConfigError < StandardError; end

      def validate_key_exists!(k)
        if !OPTIONS.include?(k)
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
