require "resque_stuck_queue/version"

# TODO move this require into a configurable?
require 'resque'

# TODO rm redis-mutex dep and just do the setnx locking here
require 'redis-mutex'

require 'logger'

module Resque
  module StuckQueue

    GLOBAL_KEY        = "resque-stuck-queue"
    HEARTBEAT         = 60 * 60 # check/refresh every hour
    TRIGGER_TIMEOUT   = 5 * 60 * 60 # warn/trigger 5 hours
    HANDLER           = proc { |queue_name| $stdout.puts("Shit gone bad with them queues...on #{queue_name}.") }

    class << self

      attr_accessor :config

      # # how often we refresh the key
      # :heartbeat  = 5 * 60
      #
      # # this could just be :heartbeat but it's possible there's an acceptable lag/bottleneck
      # # in the queue that we want to allow to be before we think it's bad.
      # :trigger_timeout = 10 * 60
      #
      # # The global key that will be used to check the latest time
      # :global_key  = "resque-stuck-queue"
      #
      # # for threads involved here. default is false
      # :abort_on_exception 
      #
      # # default handler
      # config[:handler] = proc { |queue_name| send_mail }
      #
      # # explicit redis
      # config[:redis] = Redis.new
      def config
        @config ||= {}
      end

      def logger
        @logger ||= (config[:logger] || Logger.new($stdout))
      end

      def redis
        @redis ||= (config[:redis] || Resque.redis)
      end

      def redis=(rds)
        # for resq2 tests
        @redis = rds
        Resque.redis = @redis
      end

      def global_key_for(queue)
        "#{queue}:#{config[:global_key] || GLOBAL_KEY}"
      end

      def global_keys
        queues.map{|q| global_key_for(q) }
      end

      def queues
        @queues ||= (config[:queues] || [:app])
      end

      def start_in_background
        Thread.new do
          Thread.current.abort_on_exception = config[:abort_on_exception]
          self.start
        end
      end

      # call this after setting config. once started you should't be allowed to modify it
      def start
        @running = true
        @stopped = false
        @threads = []
        config.freeze

        Redis::Classy.db = redis if Redis::Classy.db.nil?

        enqueue_repeating_refresh_job
        setup_checker_thread

        # fo-eva.
        @threads.map(&:join)

        logger.info("threads stopped")
        @stopped = true
      end

      def stop
        reset!
        # wait for clean thread shutdown
        while @stopped == false
          sleep 1
        end
        logger.info("Stopped")
      end

      def force_stop!
        logger.info("Force stopping")
        @threads.map(&:kill)
        reset!
      end

      def reset!
        # clean state so we can stop and start in the same process.
        @config = config.dup #unfreeze
        @queues = nil
        @running = false
        @logger = nil
      end

      def stopped?
        @stopped
      end

      private

      def enqueue_repeating_refresh_job
        @threads << Thread.new do
          Thread.current.abort_on_exception = config[:abort_on_exception]
          logger.info("Starting heartbeat thread")
          while @running
            # we want to go through resque jobs, because that's what we're trying to test here:
            # ensure that jobs get executed and the time is updated!
            logger.info("Sending refresh jobs")
            enqueue_jobs
            wait_for_it
          end
        end
      end

      def enqueue_jobs
        if config[:refresh_job]
          # FIXME config[:refresh_job] with mutliple queues is bad semantics
          config[:refresh_job].call
        else
          queues.each do |queue_name|
            Resque.enqueue_to(queue_name, RefreshLatestTimestamp, [global_key_for(queue_name), redis.client.host, redis.client.port])
          end
        end
      end

      def setup_checker_thread
        @threads << Thread.new do
          Thread.current.abort_on_exception = config[:abort_on_exception]
          logger.info("Starting checker thread")
          while @running
            mutex = Redis::Mutex.new('resque_stuck_queue_lock', block: 0)
            if mutex.lock
              begin
                queues.each do |queue_name|
                  if Time.now.to_i - last_time_worked(queue_name) > max_wait_time
                    logger.info("Triggering handler for #{queue_name} at #{Time.now} (pid: #{Process.pid})")
                    trigger_handler(queue_name)
                  end
                end
              ensure
                mutex.unlock
              end
            end
            wait_for_it
          end
        end
      end

      def last_time_worked(queue_name)
        time_set = read_from_redis(queue_name)
        if time_set
          time_set
        else
          manual_refresh(queue_name)
         end.to_i
      end

      def manual_refresh(queue_name)
         time = Time.now.to_i
         redis.set(global_key_for(queue_name), time)
         time
      end

      def trigger_handler(queue_name)
        (config[:handler] || HANDLER).call(queue_name)
        manual_refresh(queue_name)
      rescue => e
        logger.info("handler for #{queue_name} crashed: #{e.inspect}")
        force_stop!
      end

      def read_from_redis(queue_name)
        redis.get(global_key_for(queue_name))
      end

      def wait_for_it
        sleep config[:heartbeat] || HEARTBEAT
      end

      def max_wait_time
        config[:trigger_timeout] || TRIGGER_TIMEOUT
      end
    end
  end
end

class RefreshLatestTimestamp
  def self.perform(args)
    timestamp_key = args[0]
    host = args[1]
    port = args[2]
    r = Redis.new(:host => host, :port => port)
    r.set(timestamp_key, Time.now.to_i)
  end
end
