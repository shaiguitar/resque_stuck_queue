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

  # TODO
  # this test works, so there's nothing wrong here.
  # but when running from a rake task (readme example), rails only flushes after 1000 lines
  # if the hearbeat is longer, it will seem as if it's not logging at all :\
  # needs a way to set the logger to flush much sooner.
  #
  # logger.io.flush doesn't exist. see what rake task is using as a logger and then set it there
  # don't override global logger defaults though, that could impact production.<C-D-c>
  def test_default_logger_flushes_on_messages
    puts "#{__method__}"
    project_root = File.join(File.expand_path(File.dirname(__FILE__)), "..")
    ze_project   = File.join(project_root, "lib", "resque_stuck_queue")

    str = ""
    str << "$: << '#{project_root}'\n"
    str << "$: << '#{project_root}/lib'\n"
    str << "require '#{ze_project}'\n"
    str << "Resque::StuckQueue.start\n"

    script = File.open("/tmp/rsq.rb","w"){|f| f.write(str) }
    pid = Process.spawn("ruby /tmp/rsq.rb >/tmp/rsq.rb.log 2>&1")

    Thread.new {
      Thread.abort_on_exception = true
      sleep 2
      assert File.read("/tmp/tmplog").match(/Starting/), "should be flushed"
    }

    Thread.new {
      sleep 4
      `kill -9 #{pid}`
    }

    Process.waitpid pid
  end

end


