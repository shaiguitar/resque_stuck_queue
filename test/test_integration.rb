require 'minitest'
require "minitest/autorun"
require 'pry'


$:.unshift(".")
require 'resque_stuck_queue'
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "set_redis_key")
require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestIntegration < Minitest::Test

  include TestHelper

  # UBER HAXING no after(:all) or before(:all)
  class << self
    def tests_running?
      test_count = public_instance_methods.select{|m| m.to_s.match(/^test_/)}.size
      true if tests_ran != test_count
    end

    def tests_done?
      !tests_running?
    end

    attr_accessor :tests_ran, :resque_pid
    def tests_ran
      @tests_ran ||= 0
    end

    def run_resque_before_all
      return if @running_resque
      @running_resque = true

      @resque_pid = TestHelper.run_resque
    end
  end

  def setup
    Resque::StuckQueue.config[:redis] = Redis.new
    Resque::StuckQueue.redis.flushall
    Resque::StuckQueue.config[:watcher_interval] = 1
    Resque::StuckQueue.config[:abort_on_exception] = true
    self.class.run_resque_before_all
    self.class.tests_ran += 1
  end

  def teardown
    Resque::StuckQueue.reset!
    if self.class.tests_done?
      hax_kill_resque
      Process.waitall
    end
  end

  def test_resque_does_not_enqueue_if_queue_is_bad
    puts "#{__method__}"

    with_no_resque_failures do
      Resque::StuckQueue.config[:trigger_timeout] = 1 # force queue to be 'bad' after 1
      Resque::StuckQueue.config[:heartbeat_interval] = 1 # send one heartbeat
      Resque::StuckQueue.config[:redis] = Redis.new

      # so Resque.info[:processed] is clean
      Resque::StuckQueue.redis.flushall

      start_and_stop_loops_after(3)
      assert_equal Resque.info[:processed], 1 # otherwise would have been 3
    end
  end

  def test_resque_enqueues_a_job_does_not_trigger
    puts "#{__method__}"

    with_no_resque_failures do
      Resque::StuckQueue.config[:trigger_timeout] = 10
      Resque::StuckQueue.config[:heartbeat_interval] = 1
      Resque::StuckQueue.config[:redis] = Redis.new

      @triggered = false
      Resque::StuckQueue.config[:triggered_handler] = proc { @triggered = true }
      start_and_stop_loops_after(5)
      sleep 3 # job ran successfully, so don't trigger
      assert_equal @triggered, false
    end
  end

  # warn_interval #0
  def test_resque_does_not_enqueues_a_job_does_trigger_once_with_no_warn_interval
  puts "#{__method__}"

    with_no_resque_failures do
      Resque::StuckQueue.config[:heartbeat_interval] = 5 # so heartbeats don't go through at all in this timeframe
      Resque::StuckQueue.config[:trigger_timeout] = 2
      Resque::StuckQueue.config[:watcher_interval] = 1
      Resque::StuckQueue.config[:warn_interval] = nil
      Resque::StuckQueue.config[:redis] = Redis.new
      Resque::StuckQueue.config[:triggered_handler] = proc { Resque::StuckQueue.redis.incr("test_incr_warn") }

      start_and_stop_loops_after(5)
      # check handler did get called once as there is no warn_interval
      assert_equal Resque::StuckQueue.redis.get("test_incr_warn").to_i, 1
    end
  end


  # warn_interval #1
  def test_resque_does_not_enqueues_a_job_does_trigger_with_warn_interval
  puts "#{__method__}"

    with_no_resque_failures do
      Resque::StuckQueue.config[:heartbeat_interval] = 5 # so heartbeats don't go through at all in this timeframe
      Resque::StuckQueue.config[:trigger_timeout] = 2
      Resque::StuckQueue.config[:watcher_interval] = 1
      Resque::StuckQueue.config[:warn_interval] = 1
      Resque::StuckQueue.config[:redis] = Redis.new
      Resque::StuckQueue.config[:triggered_handler] = proc { Resque::StuckQueue.redis.incr("test_incr_warn") }

      start_and_stop_loops_after(5)
      # check handler did get called multiple times due to warn_interval
      assert_equal Resque::StuckQueue.redis.get("test_incr_warn").to_i, 3
    end
  end

  # warn_interval #2
  def test_resque_does_not_enqueues_a_job_does_trigger_with_warn_interval_stops_on_recover
  puts "#{__method__}"

    with_no_resque_failures do
      Resque::StuckQueue.config[:heartbeat_interval] = 2 # so we trigger, and recover in this timeframe
      Resque::StuckQueue.config[:trigger_timeout] = 2
      Resque::StuckQueue.config[:watcher_interval] = 1
      Resque::StuckQueue.config[:warn_interval] = 1
      Resque::StuckQueue.config[:redis] = Redis.new
      Resque::StuckQueue.config[:triggered_handler] = proc { Resque::StuckQueue.redis.incr("test_incr_warn") }

      @recovered = false
      Resque::StuckQueue.config[:recovered_handler] = proc { @recovered = true }

      start_and_stop_loops_after(5)

      assert @recovered, "resque should have picked up heartbeat job after 2 seconds"

      # check handler did get called multiple times due to warn_interval but less than previous test because recover
      assert_equal Resque::StuckQueue.redis.get("test_incr_warn").to_i, 2
    end
  end

  def test_resque_does_not_enqueues_a_job_does_trigger
    puts "#{__method__}"

    with_no_resque_failures do
      Resque::StuckQueue.config[:trigger_timeout] = 0
      Resque::StuckQueue.config[:heartbeat_interval] = 1
      Resque::StuckQueue.config[:redis] = Redis.new

      @triggered = false
      Resque::StuckQueue.config[:triggered_handler] = proc { @triggered = true }
      start_and_stop_loops_after(2)
      # check handler did get called
      assert_equal @triggered, true
    end
  end

  def test_has_settable_custom_hearbeat_job
    puts "#{__method__}"

    with_no_resque_failures do
      Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
      Resque::StuckQueue.config[:heartbeat_interval] = 1
      Resque::StuckQueue.config[:redis] = Redis.new

      begin
        Resque::StuckQueue.config[:heartbeat_job] = proc { Resque.enqueue_to(:app, Resque::StuckQueue::HeartbeatJob, Resque::StuckQueue.heartbeat_key_for(:app)) }
        @triggered = false
        Resque::StuckQueue.config[:triggered_handler] = proc { @triggered = true }
        start_and_stop_loops_after(4)

        sleep 3 # allow trigger
        assert true, "should not have raised"
        assert @triggered, "should have triggered"
      rescue => e
        assert false, "should have succeeded with good refresh_job.\n #{e.inspect}"
      end
    end
  end

end
