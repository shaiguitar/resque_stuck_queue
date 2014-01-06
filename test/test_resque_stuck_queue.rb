require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestResqueStuckQueue < Minitest::Test

  include TestHelper

  def teardown
    puts "#{__method__}"
    Resque::StuckQueue.unstub(:has_been_used?)
    Resque::StuckQueue.unstub(:read_from_redis)
  end

  def setup
    puts "#{__method__}"
    # clean previous test runs
    Resque.redis.flushall
    Resque.mock!
    Resque::StuckQueue.config[:heartbeat]   = 1 # seconds
    Resque::StuckQueue.config[:trigger_timeout] = 2
    Resque::StuckQueue.config[:abort_on_exception] = true
  end

  # usually the key will be set from previous runs since it will persist (redis) between deploys etc.
  # so you shouldn't be running into this scenario (nil key) other than
  # 0) test setup clearing out this key
  # 1) the VERY first time you use this lib when it first gets set.
  # 2) redis gets wiped out
  # 3) resque jobs never get run!
  # this has the unfortunate meaning that if no jobs are *ever* enqueued, this lib won't catch that problem.
  # so we split the funcationaliy to raise if no key is there, unless it's the first time it's being used since being started.
  def test_thread_does_not_trigger_when_no_key_exists_on_first_use
    puts "#{__method__}"

    # lib never ran, and key is not there
    Resque::StuckQueue.stubs(:has_been_used?).returns(nil)
    Resque::StuckQueue.stubs(:read_from_redis).returns(nil)
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(2)
    assert_equal false, @triggered # "handler should not be called"
  end

  def test_thread_does_trigger_when_no_key_exists_on_any_other_use
    puts "#{__method__}"
    # lib already ran, but key is not there
    Resque::StuckQueue.stubs(:has_been_used?).returns(true)
    Resque::StuckQueue.stubs(:read_from_redis).returns(nil)

    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(2)
    assert_equal true, @triggered # "handler should be called"
  end

  def test_configure_global_key
    puts "#{__method__}"
    assert_nil Resque.redis.get("it-is-configurable"), "global key should not be set"
    Resque::StuckQueue.config[:global_key] = "it-is-configurable"
    start_and_stop_loops_after(2)
    refute_nil Resque.redis.get("it-is-configurable"), "global key should be set"
  end

  def test_it_sets_a_verified_key_to_indicate_first_use
    puts "#{__method__}"
    assert_nil Resque.redis.get(Resque::StuckQueue::VERIFIED_KEY), "should be nil before lib is used"
    start_and_stop_loops_after(2)
    refute_nil Resque.redis.get(Resque::StuckQueue::VERIFIED_KEY), "should set verified key after used"
  end

  def test_it_does_not_trigger_handler_if_under_max_time
    puts "#{__method__}"
    Resque::StuckQueue.stubs(:read_from_redis).returns(Time.now.to_i)
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(2)
    assert_equal false, @triggered # "handler should not be called"
  end

  def test_it_triggers_handler_if_over_trigger_timeout
    puts "#{__method__}"
    last_time_too_old = Time.now.to_i - Resque::StuckQueue::TRIGGER_TIMEOUT
    Resque::StuckQueue.stubs(:read_from_redis).returns(last_time_too_old.to_s)
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    start_and_stop_loops_after(2)
    assert_equal true, @triggered # "handler should be called"
  end

end

