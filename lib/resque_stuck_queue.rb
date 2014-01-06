require "resque_stuck_queue/version"

# TODO rm redis-mutex dep and just do the setnx locking here
require 'redis-mutex'
Redis::Classy.db = Resque.redis

# TODO move this require into a configurable?
require 'resque'

require 'logger'

module Resque
  module StuckQueue

    GLOBAL_KEY        = "resque-stuck-queue"
    HEARTBEAT         = 60 * 60 # check/refresh every hour
    TRIGGER_TIMEOUT   = 5 * 60 * 60 # warn/trigger 5 hours
    HANDLER           = proc { $stdout.puts("Shit gone bad with them queues.") }

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
      # config[:handler] = proc { send_mail }
      def config
        @config ||= {}
      end

      def logger
        @logger ||= (config[:logger] || Logger.new($stdout))
      end

      def start_in_background
        Thread.new do
          Thread.current.abort_on_exception = config[:abort_on_exception]
          self.start
        end
      end

      def stop_in_background
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
            #
            # TODO REDIS 2.0 compat
            logger.info("Sending refresh job")
            Resque.enqueue(RefreshLatestTimestamp, global_key)
            wait_for_it
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
                if Time.now.to_i - last_time_worked > max_wait_time
                  logger.info("Triggering handler at #{Time.now} (pid: #{Process.pid})")
                  trigger_handler
                end
              ensure
                mutex.unlock
              end
            end
            wait_for_it
          end
        end
      end

      def last_time_worked
        time_set = read_from_redis
        if time_set
          time_set
        else
          manual_refresh
         end.to_i
      end

      def manual_refresh
         time = Time.now.to_i
         Resque.redis.set(global_key, time)
         time
      end

      def trigger_handler
        (config[:handler] || HANDLER).call
        manual_refresh
      rescue => e
        logger.info("handler crashed: #{e.inspect}")
        force_stop!
      end

      def read_from_redis
        Resque.redis.get(global_key)
      end

      def wait_for_it
        sleep config[:heartbeat] || HEARTBEAT
      end

      def global_key
        config[:global_key] || GLOBAL_KEY
      end

      def max_wait_time
        config[:trigger_timeout] || TRIGGER_TIMEOUT
      end
    end
  end
end

class RefreshLatestTimestamp
  @queue = :app
  def self.perform(timestamp_key)
    Resque.redis.set(timestamp_key, Time.now.to_i)
  end
end
