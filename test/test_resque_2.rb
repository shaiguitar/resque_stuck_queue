# run with
# $ RESQUE_2=1 bi; RESQUE_2=1 be ruby -I. -Ilib/ test/test_resque_2.rb
if !ENV['RESQUE_2'].nil?

  require File.join(File.expand_path(File.dirname(__FILE__)), "test_helper")

  class TestResque2 < Minitest::Test

    include TestHelper

    def setup
      assert (Resque::VERSION.match /^2\./), "must run in 2.0"
    Resque.redis = Redis.new
    Resque::StuckQueue.config[:redis] = Redis.new
      Redis.new.flushall
    end

   def test_works_with_2_point_oh_do_not_trigger_because_key_is_updated

     Resque::StuckQueue.config[:redis] = Redis.new

     Resque::StuckQueue.config[:watcher_interval] = 1
     Resque::StuckQueue.config[:heartbeat_interval] = 1
     Resque::StuckQueue.config[:abort_on_exception] = true
     Resque::StuckQueue.config[:trigger_timeout] = 5
     Resque::StuckQueue.config[:logger] = Logger.new($stdout)
     Resque::StuckQueue.config[:triggered_handler] = proc { Redis.new.incr("test-incr-key") }
     Resque::StuckQueue.config[:redis] = Redis.new
     Resque::StuckQueue.config[:queues] = [:app]

     #binding.pry
     Resque::StuckQueue.start_in_background

     @r2_pid = fork { Resque::StuckQueue.config[:redis] = Redis.new ; Resque::Worker.new("*", :graceful_term => true).work ; Process.waitall }
     sleep 10

     # triggers once
     assert_equal Redis.new.get("test-incr-key").to_i, 0
     hax_kill_resque
     Resque::StuckQueue.force_stop!
   end

  end

end
