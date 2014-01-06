require 'minitest'
require "minitest/autorun"
require 'pry'
require 'mocha'
require 'resque/mock'
$:.unshift(".")
require 'resque_stuck_queue'
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "set_redis_key")
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "refresh_latest_timestamp")

module TestHelper

  def run_resque
    pid = fork { exec("QUEUE=* bundle exec rake --trace resque:work") }
    sleep 3 # wait for resque to boot up
    pid
  end

  def start_and_stop_loops_after(secs)
    ops = []
    ops << Thread.new { Resque::StuckQueue.start }
    ops << Thread.new { sleep secs; Resque::StuckQueue.stop }
    ops.map(&:join)
  end

end
