require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestConfig < Minitest::Test

  include TestHelper

  def setup
    Resque::StuckQueue.config[:trigger_timeout] = 1
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:abort_on_exception] = true
  end

  def test_config_has_descriptions
    c = Resque::StuckQueue::Config.new
    assert c.description_for(:logger) =~ /Logger/, "has descriptions"
  end

  def test_outputs_all_config_options
    c = Resque::StuckQueue::Config.new
    puts c.pretty_descriptions
    assert true
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


