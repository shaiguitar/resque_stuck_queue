require 'minitest'
require "minitest/autorun"
require 'pry'

$:.unshift(".")
require 'resque_stuck_queue'
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "set_redis_key")
require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

class TestLagTime < Minitest::Test

  include TestHelper

  def setup
    Resque::StuckQueue.redis = Redis.new
    Resque::StuckQueue.redis.flushall
    Resque::StuckQueue.config[:abort_on_exception] = true
  end

  def test_triggers_handler_with_lagtime
    Resque::StuckQueue.config[:trigger_timeout] = 2 # won't allow waiting too much and will complain (eg trigger) sooner than later
    Resque::StuckQueue.config[:heartbeat] = 1
    @lagtime = 0
    Resque::StuckQueue.config[:triggered_handler] = proc { |queue_name, lagtime| @lagtime = lagtime }
    start_and_stop_loops_after(5)

    # check handler did get called
    assert @lagtime > 0, "lagtime shoudl be set"
    assert @lagtime < 5, "lagtime shoudl be set"
  end


end
