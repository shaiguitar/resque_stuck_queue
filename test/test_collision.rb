require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestCollision < Minitest::Test

  include TestHelper

  def test_two_processes_interacting
    puts "#{__method__}"
    # no resque should be running here so timeouts will be reached + trigger
    Resque.redis.del("test-incr-key")

    p1 = fork { Resque.redis.client.reconnect; run_resque_stuck_daemon;  }
    p2 = fork { Resque.redis.client.reconnect; run_resque_stuck_daemon;  }
    p3 = fork { Resque.redis.client.reconnect; run_resque_stuck_daemon;  }
    p4 = fork { Resque.redis.client.reconnect; run_resque_stuck_daemon;  }

    Thread.new {
      sleep 5 # let test run and trigger once occur (according to time below)
      `kill -9 #{p1}`
      `kill -9 #{p2}`
      `kill -9 #{p3}`
      `kill -9 #{p4}`
      Process.waitpid # reap
    }

    Process.waitall

    assert_equal 1, Resque.redis.get("test-incr-key").to_i
  end

  private

  def run_resque_stuck_daemon
    Resque::StuckQueue.config[:heartbeat] = 1
    Resque::StuckQueue.config[:abort_on_exception] = true
    Resque::StuckQueue.config[:trigger_timeout] = 3
    Resque::StuckQueue.config[:handler] = proc { Resque.redis.incr("test-incr-key") }
    Resque::StuckQueue.start
  end

end
