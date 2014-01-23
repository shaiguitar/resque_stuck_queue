require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestNamedQueue < Minitest::Test

  include TestHelper

  def setup
    Resque::StuckQueue.config[:trigger_timeout] = 1
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:abort_on_exception] = true
    Resque.redis.flushall
  end

  def teardown
   `kill -9 #{@resque_pid}` if @resque_pid
    Resque::StuckQueue.stop
    Process.waitpid(@resque_pid) if @resque_pid
  end

  def test_no_custom_named_queue
    puts "#{__method__}"
    Resque::StuckQueue.config[:named_queue] = nil
    start_and_stop_loops_after(2)
    assert_equal Resque::StuckQueue.global_key, "app:resque-stuck-queue"
    assert_equal Resque::StuckQueue.named_queue, :app
  end

  def test_has_custom_named_queue
    puts "#{__method__}"
    Resque::StuckQueue.config[:named_queue] = :foo
    start_and_stop_loops_after(2)
    assert_equal Resque::StuckQueue.global_key, "foo:resque-stuck-queue"
    assert_equal Resque::StuckQueue.named_queue, :foo
  end

  def test_resque_enqueues_a_job_with_resqueue_running_but_on_that_queue_does_trigger
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    Resque::StuckQueue.start_in_background

    # job gets enqueued successfully
    @resque_pid = run_resque("no-such-jobs-for-this-queue")
    sleep 2 # allow timeout to trigger

    # check handler did get called
    assert_equal @triggered, true
  end

  def test_resque_enqueues_a_job_correct_queue_does_not_trigger
    puts "#{__method__}"
    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:named_queue] = :custom_queue_name
    assert_equal Resque::StuckQueue.global_key, "custom_queue_name:resque-stuck-queue"
    @triggered = false
    Resque::StuckQueue.config[:handler] = proc { @triggered = true }
    @resque_pid = run_resque("custom_queue_name")
    Resque::StuckQueue.start_in_background
    sleep 2 # allow timeout to trigger

    # check handler did not get called
    assert_equal @triggered, false
  end



end


