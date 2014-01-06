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
    Resque.redis.flushall
    Resque.mock!
    Resque::StuckQueue.config[:heartbeat]   = 1 # seconds
    Resque::StuckQueue.config[:abort_on_exception] = true
  end

  def test_configure_global_key
    puts "#{__method__}"
    assert_nil Resque.redis.get("it-is-configurable"), "global key should not be set"
    Resque::StuckQueue.config[:global_key] = "it-is-configurable"
    start_and_stop_loops_after(2)
    refute_nil Resque.redis.get("it-is-configurable"), "global key should be set"
  end

  def test_it_does_not_trigger_handler_if_under_max_time
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 5
    Resque::StuckQueue.stubs(:read_from_redis).returns(Time.now.to_i)

    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(3)
    assert_equal false, @triggered # "handler should not be called"
  end

  def test_it_triggers_handler_if_over_trigger_timeout
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 2
    last_time_too_old = Time.now.to_i - Resque::StuckQueue::TRIGGER_TIMEOUT
    Resque::StuckQueue.stubs(:read_from_redis).returns(last_time_too_old.to_s)

    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(2)
    assert_equal true, @triggered # "handler should be called"
  end

end

