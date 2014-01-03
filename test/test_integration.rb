require 'minitest'
require "minitest/autorun"

$:.unshift(".")
require 'resque_stuck_queue'
require File.join(File.expand_path(File.dirname(__FILE__)), "resque", "set_redis_key")

# there's a better way than sleeping but I want to sleep myself.

# later
#  ps aux |grep resqu |awk '{print $2}' | xargs kill 

class TestIntegration < Minitest::Test

  def setup
  end

  def teardown
    Process.kill("SIGQUIT", @resque_pid)
    sleep 5
  end

  def run_resque
    pid = fork { exec("QUEUE=* bundle exec rake --trace resque:work") }
    sleep 3 # wait for resque to boot up
    pid
  end

  def test_resque_enques_a_job
    @resque_pid = run_resque
    Resque.redis.del(SetRedisKey::NAME)
    Resque.enqueue(SetRedisKey)
    # let resque pick up the job
    sleep 6
    assert_equal Resque.redis.get(SetRedisKey::NAME), "1"
  end

  def test_resque_does_not_enqueu_a_job
    @resque_pid = run_resque
    Resque.redis.del(SetRedisKey::NAME)

    Process.kill("SIGSTOP", @resque_pid) # do not process jobs!

    Resque.enqueue(SetRedisKey)
    # let resque pick up the job
    sleep 6
    assert_equal Resque.redis.get(SetRedisKey::NAME), nil
    raise 'in this test or similar, add the lib and ensure that the trigger gets executed!'
  end


end
