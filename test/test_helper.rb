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
   `ps aux |grep resque |awk '{print $2}' |xargs kill`
   sleep 2 # wait for shutdown
  end

  def start_and_stop_loops_after(secs)
    ops = []
    ops << Thread.new { Resque::StuckQueue.start }
    ops << Thread.new { sleep secs; Resque::StuckQueue.stop }
    ops.map(&:join)
  end

end
