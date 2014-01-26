require "resque_stuck_queue/version"
require "resque_stuck_queue/config"

# TODO move this require into a configurable?
require 'resque'

# TODO rm redis-mutex dep and just do the setnx locking here
require 'redis-mutex'

require 'logger'

module Resque
  module StuckQueue

    class << self

      attr_accessor :config

      def config
        @config ||= Config.new
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

      def heartbeat_key_for(queue)
        "#{queue}:#{config[:heartbeat_key] || HEARTBEAT_KEY}"
      end

      def triggered_key_for(queue)
        "#{queue}:#{config[:triggered_key] || TRIGGERED_KEY}"
      end

      def heartbeat_keys
        queues.map{|q| heartbeat_key_for(q) }
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
            Resque.enqueue_to(queue_name, RefreshLatestTimestamp, [heartbeat_key_for(queue_name), redis.client.host, redis.client.port])
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
                  logger.info("Checking if queue #{queue_name} is lagging")
                  # else TODO recovered?
                  if should_trigger?(queue_name)
                    logger.info("Triggering handler for #{queue_name} at #{Time.now}.")
                    logger.info("Lag time for #{queue_name} is #{lag_time(queue_name)} seconds.")
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

      #def recovered?
        # already triggered once (last_trigger is not nil), but lag time is ok.
        # then over here we'll rm last_triggered
        # and fire a recovered handler. by rm the last_triggered the next time
        # there is a problem, should_trigger? should return true
      #end

      def last_successful_heartbeat(queue_name)
        time_set = read_from_redis(heartbeat_key_for(queue_name))
        if time_set
          time_set
        else
          # the first time this is being used, key wont be there
          # so just start now.
          manual_refresh(queue_name)
         end.to_i
      end

      def manual_refresh(queue_name, type = :first_time)
        if type == :triggered
          time = Time.now.to_i
          redis.set(triggered_key_for(queue_name), time)
          time
        elsif type == :first_time
          time = Time.now.to_i
          redis.set(heartbeat_key_for(queue_name), time)
          time
        end
      end

      def lag_time(queue_name)
        Time.now.to_i - last_successful_heartbeat(queue_name)
      end

      def last_triggered(queue_name)
        time_set = read_from_redis(triggered_key_for(queue_name))
        if !time_set.nil?
          Time.now.to_i - time_set.to_i
        end
      end

      def should_trigger?(queue_name)
        if lag_time(queue_name) > max_wait_time
          last_trigger = last_triggered(queue_name)

          if last_trigger.nil?
            return true
          elsif last_trigger > max_wait_time
            return true
          else
            # if we've already triggered, the next trigger should be on the next iteration of max_wait_time.
            return false
          end
        end
      end

      def trigger_handler(queue_name)
        (config[:handler] || HANDLER).call(queue_name, lag_time(queue_name))
        manual_refresh(queue_name, :triggered)
      rescue => e
        logger.info("handler for #{queue_name} crashed: #{e.inspect}")
        logger.info("\n#{e.backtrace.join("\n")}")
        force_stop!
      end

      def read_from_redis(keyname)
        redis.get(keyname)
      end

      def wait_for_it
        sleep config[:heartbeat] || HEARTBEAT_TIMEOUT
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
