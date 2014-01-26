require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestNamedQueues < Minitest::Test

  include TestHelper

  def setup
    Resque::StuckQueue.config[:trigger_timeout] = 1
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:abort_on_exception] = true
    Resque::StuckQueue.redis = Redis.new
    Resque::StuckQueue.redis.flushall
  end

  def teardown
    hax_kill_resque
    Resque::StuckQueue.force_stop!
    Process.waitpid(@resque_pid) if @resque_pid
  end

  def test_no_custom_queues_defaults_to_app
    puts "#{__method__}"
    Resque::StuckQueue.config[:queues] = nil
    start_and_stop_loops_after(2)
    assert Resque::StuckQueue.heartbeat_keys.include?("app:resque-stuck-queue"), 'has global keys'
  end

  def test_has_custom_queues
    puts "#{__method__}"
    Resque::StuckQueue.config[:queues] = [:foo,:bar]
    start_and_stop_loops_after(2)
    assert Resque::StuckQueue.heartbeat_keys.include?("foo:resque-stuck-queue"), 'has global keys'
  end

  def test_resque_enqueues_a_job_with_resqueue_running_but_on_that_queue_does_trigger
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:queues] = [:custom_queue_name]
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { |queue_name| @triggered = queue_name }
    Resque::StuckQueue.start_in_background

    # job gets enqueued successfully
    @resque_pid = run_resque("no-such-jobs-for-this-queue")
    sleep 2 # allow timeout to trigger

    # check handler did get called
    assert_equal @triggered, :custom_queue_name
  end

  def test_resque_enqueues_a_job_correct_queue_does_not_trigger
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:queues] = [:custom_queue_name, :diff_one]
    assert Resque::StuckQueue.heartbeat_keys.include?("custom_queue_name:resque-stuck-queue"), 'has global keys'
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    @resque_pid = run_resque("custom_queue_name")
    Resque::StuckQueue.start_in_background
    sleep 2 # allow timeout to trigger

    # check handler did not get called
    assert_equal @triggered, false
  end

end


