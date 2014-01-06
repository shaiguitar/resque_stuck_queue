require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestResqueStuckQueue < Minitest::Test

  include TestHelper

  def setup
    Resque::StuckQueue.config[:trigger_timeout] = 1
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:abort_on_exception] = true
  end

  def teardown
    Resque::StuckQueue.reset!
  end

  def test_has_logger
    puts "#{__method__}"
    begin
      Resque::StuckQueue.config[:logger] = Logger.new($stdout)
      start_and_stop_loops_after(2)
      assert true, "should not have raised"
    rescue
      assert false, "should have succeeded with good logger"
    end
  end

end


