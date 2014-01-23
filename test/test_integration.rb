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
  # TODODS there's a better way to do this.
  #
  #
  # run test with  VVERBOSE=1 DEBUG=1 for more output
  #
  #
  # => sleeping suckc
  # => resque sleeps 5 between checking enqueed jobs, can be configurable?
  #
  # cleanup processes correctly?
  # ps aux |grep resqu |awk '{print $2}' | xargs kill

  def setup
  end

  def teardown
   `kill -9 #{@resque_pid}` # CONT falls throughs sometimes? hax, rm this and SIGSTOP/SIGCONT
    Resque::StuckQueue.stop
    Process.waitpid(@resque_pid)
  end

  def test_resque_enqueues_a_job_does_not_trigger
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 100 # wait a while so we don't trigger
    Resque::StuckQueue.config[:heartbeat] = 2
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    Thread.new { Resque::StuckQueue.start }

    # job gets enqueued successfully
    @resque_pid = run_resque
    Resque.redis.del(SetRedisKey::NAME)
    Resque.enqueue(SetRedisKey)
    sleep 6 # let resque pick up the job
    assert_equal Resque.redis.get(SetRedisKey::NAME), "1"

    # check handler did not get called
    assert_equal @triggered, false
  end

  def test_resque_does_not_enqueues_a_job_does_trigger
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    Thread.new { Resque::StuckQueue.start }

    # job gets enqueued successfully
    @resque_pid = run_resque
    Resque.redis.del(SetRedisKey::NAME)
    Process.kill("SIGSTOP", @resque_pid) # jic, do not process jobs so we definitely trigger
    Resque.enqueue(SetRedisKey)
    assert_equal Resque.redis.get(SetRedisKey::NAME), nil
    sleep 2 # allow timeout to trigger

    # check handler did get called
    assert_equal @triggered, true

    # unstick the process so we can kill it in teardown
    Process.kill("SIGCONT", @resque_pid)
  end

  def test_has_settable_custom_hearbeat_job
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1

    begin
      Resque::StuckQueue.config[:refresh_job] = proc { Resque.enqueue(RefreshLatestTimestamp, Resque::StuckQueue.global_key_for(:app)) }
      @triggered = false
      Resque::StuckQueue.config[:handler] = proc { @triggered = true }
      Thread.new { Resque::StuckQueue.start }

      @resque_pid = run_resque
      sleep 3 # allow trigger
      assert true, "should not have raised"
      assert @triggered, "should have triggered"
    rescue => e
      assert false, "should have succeeded with good refresh_job.\n #{e.inspect}"
    end
  end


end
