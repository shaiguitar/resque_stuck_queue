require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestNamedQueue < Minitest::Test

  include TestHelper

  def setup
    Resque::StuckQueue.config[:trigger_timeout] = 1
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:abort_on_exception] = true
  end

  def teardown
    Resque::StuckQueue.reset!
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

end


