require 'minitest'
require "minitest/autorun"
require 'pry'
require 'mocha'
require "minitest/unit"
require "mocha/mini_test"
$:.unshift(".")
require 'resque_stuck_queue'
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "set_redis_key")

module TestHelper

  extend self

  def run_resque(queue_name = "*")
    pid = fork { exec("export INTERVAL=1 QUEUE=#{queue_name}; bundle exec rake --trace resque:work") }
    sleep 3 # wait for resque to boot up
    pid
  end

  def with_no_resque_failures(&blk)
    Resque::Failure.clear
    blk.call
    assert_nil Resque::Failure.all, "Resque hearbeat job cant fail: #{Resque::Failure.all.inspect}"
  end

  def hax_kill_resque
    # ugly, FIXME how to get pid of forked forked process. run_resque pid is incorrect.
   `ps aux |grep resque | grep -v stuck_queue |awk '{print $2}' |xargs kill`
   sleep 2 # wait for shutdown
  end

  def start_and_stop_loops_after(secs)
    abort_or_not = Thread.abort_on_exception
    Thread.abort_on_exception = Resque::StuckQueue.config[:abort_on_exception]

    ops = []
    ops << Thread.new { Resque::StuckQueue.start }
    ops << Thread.new { sleep secs; Resque::StuckQueue.stop }
    ops.map(&:join)

  ensure
    Thread.abort_on_exception = abort_or_not
    Resque::StuckQueue.force_stop!
  end

end

# http://stackoverflow.com/questions/9346101/how-to-get-stack-trace-from-a-testunittestcase
def MiniTest.filter_backtrace(bt)
  bt
end

# hax ensure previous test runs that raised didn't leave a resque process runing beforehand
unless @before_all_hax_kill_resque
  TestHelper.hax_kill_resque && @before_all_hax_kill_resque=true
end
