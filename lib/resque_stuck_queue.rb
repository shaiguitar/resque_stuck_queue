require "resque_stuck_queue/version"
require "resque_stuck_queue/config"
require "resque_stuck_queue/heartbeat_job"
require "resque_stuck_queue/signals"

require 'redis-namespace'

# TODO move this require into a configurable?
require 'resque'

# TODO rm redis-mutex dep and just do the setnx locking here
require 'redis-mutex'

module Resque
  module StuckQueue

    class << self

      attr_accessor :config

      def config
        @config ||= Config.new
      end

      def logger
        @logger ||= (config[:logger] || StuckQueue::LOGGER)
      end

      def redis
        @redis ||= config[:redis]
      end

      def heartbeat_key_for(queue)
        if config[:heartbeat_key]
          "#{queue}:#{config[:heartbeat_key]}"
        else
          "#{queue}:#{HEARTBEAT_KEY}"
        end
      end

      def triggered_key_for(queue)
        if config[:triggered_key]
          "#{queue}:#{self.config[:triggered_key]}"
        else
          "#{queue}:#{TRIGGERED_KEY}"
        end
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
        config.validate_required_keys!
        config.freeze

        Signals.enable!

        log_starting_info

        reset_keys

        Redis::Classy.db = redis if Redis::Classy.db.nil?

        pretty_process_name

        setup_heartbeat_thread
        setup_watcher_thread

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
        @config = Config.new # clear, unfreeze
        @queues = nil
        @running = false
        @logger = nil
      end

      def reset_keys
        queues.each do |qn|
          redis.del(heartbeat_key_for(qn))
          redis.del(triggered_key_for(qn))
        end
      end

      def stopped?
        @stopped
      end

      private

      def setup_heartbeat_thread
        @threads << Thread.new do
          Thread.current.abort_on_exception = config[:abort_on_exception]
          logger.info("Starting heartbeat thread")
          while @running
            # we want to go through resque jobs, because that's what we're trying to test here:
            # ensure that jobs get executed and the time is updated!
            logger.info("Sending heartbeat jobs")
            enqueue_jobs
            wait_for_it
          end
        end
      end

      def enqueue_jobs
        if config[:heartbeat_job]
          # FIXME config[:heartbeat_job] with mutliple queues is bad semantics
          config[:heartbeat_job].call
        else
          queues.each do |queue_name|
            # Redis::Namespace.new support as well as Redis.new
            namespace = redis.respond_to?(:namespace) ? redis.namespace : nil
            Resque.enqueue_to(queue_name, HeartbeatJob, heartbeat_key_for(queue_name), redis.client.host, redis.client.port, namespace, Time.now.to_i )
          end
        end
      end

      def setup_watcher_thread
        @threads << Thread.new do
          Thread.current.abort_on_exception = config[:abort_on_exception]
          logger.info("Starting checker thread")
          while @running
            mutex = Redis::Mutex.new('resque_stuck_queue_lock', block: 0)
            if mutex.lock
              begin
                queues.each do |queue_name|
                  log_checker_info(queue_name)
                  if should_trigger?(queue_name)
                    trigger_handler(queue_name, :triggered)
                  elsif should_recover?(queue_name)
                    trigger_handler(queue_name, :recovered)
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

      def last_successful_heartbeat(queue_name)
        time_set = read_from_redis(heartbeat_key_for(queue_name))
        if time_set
          time_set
        else
          logger.info("manually refreshing #{queue_name} for :first_time")
          manual_refresh(queue_name, :first_time)
         end.to_i
      end

      def manual_refresh(queue_name, type)
        if type == :triggered
          time = Time.now.to_i
          redis.set(triggered_key_for(queue_name), time)
          time
        elsif type == :recovered
          redis.del(triggered_key_for(queue_name))
          nil
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

      def should_recover?(queue_name)
        last_triggered(queue_name) &&
          lag_time(queue_name) < max_wait_time
      end

      def should_trigger?(queue_name)
        if lag_time(queue_name) >= max_wait_time
          last_trigger = last_triggered(queue_name)

          if last_trigger.nil?
            return true
          else
            # if it already triggered in the past and needs to re-trigger,
            # :recovered should have cleared last_triggered out by then
            return false
          end
        end
      end

      def trigger_handler(queue_name, type)
        raise 'Must trigger either the recovered or triggered handler!' unless (type == :recovered || type == :triggered)
        handler_name = :"#{type}_handler"
        logger.info("Triggering #{type} handler for #{queue_name} at #{Time.now}.")
        (config[handler_name] || const_get(handler_name.upcase)).call(queue_name, lag_time(queue_name))
        manual_refresh(queue_name, type)
      rescue => e
        logger.info("handler #{type} for #{queue_name} crashed: #{e.inspect}")
        logger.info("\n#{e.backtrace.join("\n")}")
        force_stop!
      end

      def log_starting_info
        logger.info("Starting StuckQueue with config: #{self.config.inspect}")
      end

      def log_checker_info(queue_name)
        logger.info("Lag time for #{queue_name} is #{lag_time(queue_name).inspect} seconds.")
        if triggered_ago = last_triggered(queue_name)
          logger.info("Last triggered for #{queue_name} is #{triggered_ago.inspect} seconds.")
        else
          logger.info("No last trigger found for #{queue_name}.")
        end

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

      def pretty_process_name
        $0 = "rake --trace resque:stuck_queue #{redis.inspect} QUEUES=#{queues.join(",")}"
      end

    end
  end
end

