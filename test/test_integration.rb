require 'minitest'
require "minitest/autorun"
require 'pry'


$:.unshift(".")
require 'resque_stuck_queue'
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "set_redis_key")
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "refresh_latest_timestamp")
require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestIntegration < Minitest::Test

  include TestHelper

  # UBER HAXING no after(:all) or before(:all)
  # if adding a test here, add
  # self.class.tests_ran += 1
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
    Resque::StuckQueue.redis = Redis.new
    Resque::StuckQueue.redis.flushall
    Resque::StuckQueue.config[:abort_on_exception] = true
    self.class.run_resque_before_all
  end

  def teardown
    if self.class.tests_done?
      hax_kill_resque
      Process.waitall
      return
    end
  end

  def test_resque_enqueues_a_job_does_not_trigger
    puts "#{__method__}"
    self.class.tests_ran += 1

    Resque::StuckQueue.config[:trigger_timeout] = 10
    Resque::StuckQueue.config[:heartbeat] = 1
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(5)
    Resque::StuckQueue.redis.del(SetRedisKey::NAME)
    Resque.enqueue_to(:app, SetRedisKey)
    sleep 3
    assert_equal Resque::StuckQueue.redis.get(SetRedisKey::NAME), "1"
    # job ran successfully, so don't trigger
    assert_equal @triggered, false
  end

  def test_resque_does_not_enqueues_a_job_does_trigger
    puts "#{__method__}"
    self.class.tests_ran += 1

    Resque::StuckQueue.config[:trigger_timeout] = 0
    Resque::StuckQueue.config[:heartbeat] = 1
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(2)
    # check handler did get called
    assert_equal @triggered, true
  end

  def test_has_settable_custom_hearbeat_job
    puts "#{__method__}"
    self.class.tests_ran += 1

    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1

    begin
      Resque::StuckQueue.config[:refresh_job] = proc { Resque.enqueue(RefreshLatestTimestamp, Resque::StuckQueue.heartbeat_key_for(:app)) }
      @triggered = false
      Resque::StuckQueue.config[:handler] = proc { @triggered = true }
      start_and_stop_loops_after(4)

      sleep 3 # allow trigger
      assert true, "should not have raised"
      assert @triggered, "should have triggered"
    rescue => e
      assert false, "should have succeeded with good refresh_job.\n #{e.inspect}"
    end
  end

end
