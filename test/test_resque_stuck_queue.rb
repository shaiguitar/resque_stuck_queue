require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestResqueStuckQueue < Minitest::Test

  include TestHelper

  def teardown
    puts "#{__method__}"
    Resque::StuckQueue.unstub(:read_from_redis)
  end

  def setup
    puts "#{__method__}"
    # clean previous test runs
    Resque::StuckQueue.config[:redis] = Redis.new
    Resque::StuckQueue.config[:watcher_interval] = 1
    Resque::StuckQueue.redis.flushall
    Resque::StuckQueue.config[:heartbeat_interval]   = 1 # seconds
    Resque::StuckQueue.config[:abort_on_exception] = true
  end

  def test_configure_heartbeat_key
    puts "#{__method__}"
    assert_nil Resque::StuckQueue.redis.get("it-is-configurable"), "global key should not be set"
    Resque::StuckQueue.config[:heartbeat_key] = "it-is-configurable"
    start_and_stop_loops_after(3)
    refute_nil Resque::StuckQueue.redis.get("app:it-is-configurable"), "global key should be set"
  end

  def test_it_does_not_trigger_handler_if_under_max_time
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 5
    Resque::StuckQueue.stubs(:read_from_redis).returns(Time.now.to_i)

    @triggered = false
    Resque::StuckQueue.config[:triggered_handler] = proc { @triggered = true }
    start_and_stop_loops_after(3)
    assert_equal false, @triggered # "handler should not be called"
  end

  def test_stops_if_handler_raises
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 1 # wait a short time, will trigger
    last_time_too_old = Time.now.to_i - Resque::StuckQueue::TRIGGER_TIMEOUT
    Resque::StuckQueue.config[:triggered_handler] = proc { raise "handler had bad sad!" }
    Thread.new {
      sleep 3 # should have triggered
      Thread.current.abort_on_exception = true
      assert Resque::StuckQueue.stopped?, "should stop stuck_queue if handler raises."
    }
    start_and_stop_loops_after(4)
  end

end

